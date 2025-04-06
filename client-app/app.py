import os
import json
import atexit
import signal
import secrets
from flask import Flask, redirect, url_for, session, render_template, request, jsonify
from authlib.integrations.flask_client import OAuth
import hvac
import requests
from dotenv import load_dotenv
from datetime import datetime

# Load environment variables from .env file if it exists
load_dotenv()

app = Flask(__name__)
# Generate a random secret key on startup to ensure sessions don't persist between restarts
app.secret_key = os.environ.get('FLASK_SECRET_KEY') or secrets.token_hex(16)
print(f"Flask app initialized with new secret key: {app.secret_key[:5]}...")

# Vault configuration
VAULT_ADDR = os.environ.get('VAULT_ADDR', 'http://localhost:8201')
VAULT_TOKEN = os.environ.get('VAULT_TOKEN', 'root')

# For compatibility, still initialize hvac client
vault_client = hvac.Client(
    url=VAULT_ADDR,
    token=VAULT_TOKEN
)

# Keycloak configuration
# Internal URL for server-to-server communication
KEYCLOAK_INTERNAL_URL = os.environ.get('KEYCLOAK_URL', 'http://localhost:8080')
# External URL for browser redirects
KEYCLOAK_EXTERNAL_URL = os.environ.get('KEYCLOAK_EXTERNAL_URL', 'http://localhost:8080')
REALM = os.environ.get('REALM', 'fresh-realm')
CLIENT_ID = os.environ.get('CLIENT_ID', 'fresh-client')

# Function to get client secret directly using HTTP API
def get_client_secret():
    vault_path = f"kv/data/keycloak/clients/{REALM}/{CLIENT_ID}"
    headers = {"X-Vault-Token": VAULT_TOKEN}
    response = requests.get(f"{VAULT_ADDR}/v1/{vault_path}", headers=headers)
    
    if response.status_code == 200:
        data = response.json()
        return data['data']['data']['client_secret']
    else:
        raise Exception(f"Failed to get client secret from Vault: {response.text}")

# OAuth configuration
oauth = OAuth(app)
keycloak = oauth.register(
    name='keycloak',
    client_id=CLIENT_ID,
    client_secret=None,  # We'll get this from Vault
    server_metadata_url=f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/.well-known/openid-configuration",
    client_kwargs={
        'scope': 'openid email profile'
    }
)

# Function to clear sessions in Keycloak when shutting down
def clear_sessions_on_shutdown():
    print("Shutting down Flask app, cleaning up sessions...")
    try:
        # Get admin access token
        admin_token_url = f"{KEYCLOAK_INTERNAL_URL}/realms/master/protocol/openid-connect/token"
        admin_payload = {
            'grant_type': 'password',
            'client_id': 'admin-cli',
            'username': os.environ.get('KEYCLOAK_ADMIN', 'admin'),
            'password': os.environ.get('KEYCLOAK_ADMIN_PASSWORD', 'admin')
        }
        admin_response = requests.post(admin_token_url, data=admin_payload)
        if admin_response.status_code == 200:
            admin_token = admin_response.json().get('access_token')
            
            # Get all sessions for the realm
            sessions_url = f"{KEYCLOAK_INTERNAL_URL}/admin/realms/{REALM}/client-sessions/{CLIENT_ID}"
            headers = {'Authorization': f'Bearer {admin_token}'}
            
            # Delete all sessions for this client
            logout_url = f"{KEYCLOAK_INTERNAL_URL}/admin/realms/{REALM}/clients/{CLIENT_ID}/logout-all"
            logout_response = requests.post(logout_url, headers=headers)
            
            if logout_response.status_code in [200, 204]:
                print(f"Successfully cleared all sessions for client {CLIENT_ID}")
            else:
                print(f"Failed to clear sessions: {logout_response.status_code} - {logout_response.text}")
    except Exception as e:
        print(f"Error clearing sessions: {str(e)}")

# Register the shutdown function
atexit.register(clear_sessions_on_shutdown)

# Also handle SIGTERM signal (sent by Docker when stopping container)
def handle_sigterm(signum, frame):
    print("Received SIGTERM signal")
    clear_sessions_on_shutdown()
    exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)

# Home page
@app.route('/')
def home():
    user_info = session.get('user')
    return render_template('index.html', user=user_info)

# Login endpoint
@app.route('/login')
def login():
    # Get the latest client secret from Vault
    try:
        client_secret = get_client_secret()
        
        # Update the client secret in the OAuth config
        keycloak.client_secret = client_secret
        
        # Log the retrieval (only in development)
        print(f"Retrieved client secret from Vault: {client_secret[:5]}...")
        
        # Set the redirect_uri and authorization_endpoint
        redirect_uri = url_for('auth', _external=True)
        # Use the browser-accessible URL for authorization endpoint
        authorization_endpoint = f"{KEYCLOAK_EXTERNAL_URL}/realms/{REALM}/protocol/openid-connect/auth"
        token_endpoint = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/protocol/openid-connect/token"
        
        # Manually build the authorization URL
        params = {
            'client_id': CLIENT_ID,
            'redirect_uri': redirect_uri,
            'response_type': 'code',
            'scope': 'openid email profile'
        }
        auth_url = authorization_endpoint + '?' + '&'.join([f"{k}={v}" for k, v in params.items()])
        
        # Redirect to Keycloak login
        return redirect(auth_url)
    except Exception as e:
        return render_template('error.html', error=str(e))

# Auth callback endpoint
@app.route('/auth')
def auth():
    try:
        # Get the code from the request
        code = request.args.get('code')
        if not code:
            print("ERROR: No authorization code received")
            return render_template('error.html', error="No authorization code received")
        
        # Get client secret
        try:
            client_secret = get_client_secret()
            print(f"Got client secret: {client_secret[:5]}...")
        except Exception as e:
            print(f"ERROR getting client secret: {str(e)}")
            return render_template('error.html', error=f"Failed to get client secret: {str(e)}")
        
        # Manually exchange the code for a token
        token_endpoint = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/protocol/openid-connect/token"
        redirect_uri = url_for('auth', _external=True)
        data = {
            'client_id': CLIENT_ID,
            'client_secret': client_secret,
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirect_uri
        }
        print(f"Sending token request to: {token_endpoint}")
        print(f"With data: {data}")
        
        response = requests.post(token_endpoint, data=data)
        
        print(f"Token response status: {response.status_code}")
        print(f"Token response: {response.text[:200]}...")
        
        if response.status_code != 200:
            return render_template('error.html', error=f"Failed to get token: {response.text}")
        
        token = response.json()
        
        # Skip the userinfo endpoint and just use the access token's payload
        # The access token contains identity information that we can use directly
        try:
            # Parse the access token (JWT) to get user info
            import base64
            import json
            
            # Split the token into header, payload, and signature
            token_parts = token['access_token'].split('.')
            if len(token_parts) != 3:
                raise ValueError("Invalid token format")
                
            # Get the payload (second part)
            payload_encoded = token_parts[1]
            # Add padding if needed
            padding = '=' * (4 - len(payload_encoded) % 4)
            payload_encoded += padding
            
            # Decode the base64url encoded payload
            payload_json = base64.b64decode(payload_encoded).decode('utf-8')
            payload = json.loads(payload_json)
            
            print(f"Extracted user info from token: {str(payload)[:200]}...")
            
            # Extract basic user info
            userinfo = {
                'sub': payload.get('sub'),
                'preferred_username': payload.get('preferred_username'),
                'email': payload.get('email'),
                'name': payload.get('name')
            }
            
            # Store in session
            session['user'] = userinfo
            session['access_token'] = token.get('access_token')
            session['refresh_token'] = token.get('refresh_token')
            session['token_expires'] = datetime.now().timestamp() + token.get('expires_in', 300)
            
            return redirect('/')
        except Exception as e:
            print(f"Error extracting user info from token: {str(e)}")
            return render_template('error.html', error=f"Failed to extract user info from token: {str(e)}")
    except Exception as e:
        import traceback
        print(f"ERROR in auth: {str(e)}")
        print(traceback.format_exc())
        return render_template('error.html', error=str(e))

# Logout endpoint
@app.route('/logout')
def logout():
    # First get the refresh token if available (used for Keycloak logout)
    refresh_token = session.get('refresh_token')
    
    # Clear Flask session
    session.pop('user', None)
    session.pop('access_token', None)
    session.pop('refresh_token', None)
    session.clear()
    
    # If we have a refresh token, properly logout from Keycloak too
    if refresh_token:
        try:
            # Call Keycloak logout endpoint
            logout_url = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/protocol/openid-connect/logout"
            payload = {
                'client_id': CLIENT_ID,
                'client_secret': get_client_secret(),
                'refresh_token': refresh_token
            }
            requests.post(logout_url, data=payload)
        except Exception as e:
            print(f"Error during Keycloak logout: {e}")
    
    # Redirect to Keycloak login page after logout to force re-login
    login_url = f"{KEYCLOAK_EXTERNAL_URL}/realms/{REALM}/protocol/openid-connect/auth"
    params = {
        'client_id': CLIENT_ID,
        'redirect_uri': url_for('auth', _external=True),
        'response_type': 'code',
        'scope': 'openid email profile'
    }
    keycloak_login_url = login_url + '?' + '&'.join([f"{k}={v}" for k, v in params.items()])
    
    return redirect(keycloak_login_url)

# Protected API endpoint example
@app.route('/api/profile')
def api_profile():
    if 'access_token' not in session:
        return jsonify({'error': 'Unauthorized'}), 401
    
    # Use the access token to make authenticated requests
    try:
        headers = {'Authorization': f"Bearer {session['access_token']}"}
        userinfo_url = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/protocol/openid-connect/userinfo"
        response = requests.get(userinfo_url, headers=headers)
        
        if response.status_code == 200:
            return jsonify(response.json())
        else:
            return jsonify({'error': f"Failed to fetch profile: {response.text}"}), response.status_code
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Status endpoint to check integration
@app.route('/api/status')
def status():
    # Check if user is authenticated
    if 'user' not in session:
        return jsonify({'error': 'Unauthorized - Please login first'}), 401
        
    try:
        # Check Vault status
        vault_status = vault_client.sys.read_health_status(method='GET')
        
        # Check Keycloak status
        keycloak_url = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/.well-known/openid-configuration"
        keycloak_response = requests.get(keycloak_url)
        
        return jsonify({
            'vault': {
                'status': 'OK' if vault_status.get('initialized') else 'Not initialized',
                'sealed': vault_status.get('sealed', True)
            },
            'keycloak': {
                'status': 'OK' if keycloak_response.status_code == 200 else 'Error',
                'statusCode': keycloak_response.status_code
            }
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Direct token endpoint for client credentials flow (machine-to-machine)
@app.route('/api/direct-token')
def direct_token():
    # Check if user is authenticated
    if 'user' not in session:
        return jsonify({'error': 'Unauthorized - Please login first'}), 401
        
    try:
        # Get client secret from Vault
        client_secret = get_client_secret()
        
        # Get token using client credentials
        token_url = f"{KEYCLOAK_INTERNAL_URL}/realms/{REALM}/protocol/openid-connect/token"
        payload = {
            'grant_type': 'client_credentials',
            'client_id': CLIENT_ID,
            'client_secret': client_secret
        }
        response = requests.post(token_url, data=payload)
        
        if response.status_code == 200:
            token_data = response.json()
            # Only show part of the token for security
            if 'access_token' in token_data:
                token_preview = token_data['access_token'][:20] + '...'
                token_data['access_token'] = token_preview
            return jsonify(token_data)
        else:
            return jsonify({'error': f"Failed to get token: {response.text}"}), response.status_code
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True) 