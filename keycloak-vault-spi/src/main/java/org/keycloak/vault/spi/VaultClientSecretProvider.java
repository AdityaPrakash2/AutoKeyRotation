package org.keycloak.vault.spi;

import java.io.IOException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.UUID;

import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;
import org.jboss.logging.Logger;
import org.json.JSONException;
import org.json.JSONObject;
import org.keycloak.models.ClientModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.provider.Provider;

/**
 * A provider for managing client secrets with Vault integration.
 */
public class VaultClientSecretProvider implements Provider {
    private static final Logger logger = Logger.getLogger(VaultClientSecretProvider.class);
    
    // Field constants
    private static final String ACTIVE_SECRET_FIELD = "active";
    private static final String SECRETS_FIELD = "secrets";
    private static final String CREATED_FIELD = "created";
    
    // Client attributes
    private static final String USE_VAULT_SECRET_ATTR = "use-vault-secret";
    private static final String VAULT_SECRET_PATH_ATTR = "vault-secret-path";
    
    private final KeycloakSession session;
    private final String vaultUrl;
    private final String vaultToken;
    private final String secretsBasePath;
    private final HttpClient httpClient;
    
    public VaultClientSecretProvider(KeycloakSession session, VaultClientSecretProviderConfig config) {
        this.session = session;
        this.vaultUrl = config.getVaultUrl();
        this.vaultToken = config.getVaultToken();
        this.secretsBasePath = config.getSecretsBasePath();
        this.httpClient = HttpClients.createDefault();
    }
    
    /**
     * Determines if a client is configured to use Vault for secrets
     * @param client The client to check
     * @return true if the client should use Vault, false otherwise
     */
    public boolean shouldUseVaultForClient(ClientModel client) {
        if (client == null) {
            return false;
        }
        
        String useVault = client.getAttribute(USE_VAULT_SECRET_ATTR);
        return "true".equalsIgnoreCase(useVault);
    }
    
    /**
     * Gets the specific vault path for a client if configured
     * @param client The client to check
     * @return The custom Vault path, or null if not specified
     */
    public String getClientVaultPath(ClientModel client) {
        if (client == null) {
            return null;
        }
        
        return client.getAttribute(VAULT_SECRET_PATH_ATTR);
    }
    
    /**
     * Verifies a client's secret against what is stored in Vault
     * @param client The client
     * @param secret The secret to verify
     * @return true if the secret matches what's in Vault, false otherwise
     */
    public boolean verifyClientSecret(ClientModel client, String secret) {
        if (client == null || secret == null) {
            return false;
        }
        
        // Only use Vault if the client is configured to do so
        if (!shouldUseVaultForClient(client)) {
            logger.debugf("Client '%s' is not configured to use Vault for secrets", client.getClientId());
            return false;
        }
        
        // Get the client's configured Vault path or use the default
        String vaultPath = getClientVaultPath(client);
        if (vaultPath == null) {
            vaultPath = secretsBasePath + "/" + client.getRealm().getName() + "/" + client.getClientId();
        }
        
        try {
            // Get current secrets from Vault
            JSONObject data = getCurrentSecretsFromVault(vaultPath);
            if (data == null) {
                logger.errorf("No data found in Vault at path '%s'", vaultPath);
                return false;
            }
            
            // Get active secret ID
            String activeSecretId = data.optString(ACTIVE_SECRET_FIELD);
            if (activeSecretId == null || activeSecretId.isEmpty()) {
                logger.errorf("No active secret ID found in Vault at path '%s'", vaultPath);
                return false;
            }
            
            // Get secrets object
            JSONObject secretsObj = data.optJSONObject(SECRETS_FIELD);
            if (secretsObj == null) {
                logger.errorf("No secrets object found in Vault at path '%s'", vaultPath);
                return false;
            }
            
            // Get active secret
            JSONObject secretData = secretsObj.optJSONObject(activeSecretId);
            if (secretData == null) {
                logger.errorf("Active secret with ID '%s' not found in Vault at path '%s'", activeSecretId, vaultPath);
                return false;
            }
            
            // Get secret value
            String secretValue = secretData.optString("value");
            if (secretValue == null || secretValue.isEmpty()) {
                logger.errorf("No value found for active secret with ID '%s' in Vault at path '%s'", activeSecretId, vaultPath);
                return false;
            }
            
            // Compare the secrets
            boolean result = secretValue.equals(secret);
            if (result) {
                logger.debugf("Successfully verified client secret for client '%s' from Vault", client.getClientId());
            } else {
                logger.warnf("Client secret verification failed for client '%s' using Vault", client.getClientId());
            }
            
            return result;
            
        } catch (Exception e) {
            logger.errorf("Error verifying client secret from Vault: %s", e.getMessage());
            return false;
        }
    }

    /**
     * Generates a new client secret
     * @return The newly generated secret
     */
    public String generateClientSecret() {
        SecureRandom random = new SecureRandom();
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    
    /**
     * Rotates a client secret for the specified client
     * @param realmName The realm name
     * @param clientId The client ID
     * @return The new client secret
     */
    public String rotateClientSecret(String realmName, String clientId) {
        RealmModel realm = session.realms().getRealmByName(realmName);
        if (realm == null) {
            logger.errorf("Realm '%s' not found", realmName);
            return null;
        }
        
        ClientModel client = realm.getClientByClientId(clientId);
        if (client == null) {
            logger.errorf("Client '%s' not found in realm '%s'", clientId, realmName);
            return null;
        }
        
        // Generate new client secret
        String newSecret = generateClientSecret();
        
        // Store the secret in Vault
        if (!storeClientSecretInVault(realmName, clientId, newSecret)) {
            logger.errorf("Failed to store client secret in Vault for client '%s'", clientId);
            return null;
        }
        
        // Update the client secret in Keycloak
        try {
            // Directly set the secret on the client model
            client.setSecret(newSecret);
            
            // Mark the client to use Vault for secrets
            client.setAttribute(USE_VAULT_SECRET_ATTR, "true");
            String vaultPath = secretsBasePath + "/" + realmName + "/" + clientId;
            client.setAttribute(VAULT_SECRET_PATH_ATTR, vaultPath);
            
            logger.infof("Successfully rotated client secret for client '%s' in realm '%s'", clientId, realmName);
            return newSecret;
        } catch (Exception e) {
            logger.errorf("Failed to update client secret in Keycloak: %s", e.getMessage());
            return null;
        }
    }
    
    /**
     * Stores a client secret in Vault
     * @param realmName The realm name
     * @param clientId The client ID
     * @param secret The client secret
     * @return True if successful, false otherwise
     */
    public boolean storeClientSecretInVault(String realmName, String clientId, String secret) {
        String vaultPath = secretsBasePath + "/" + realmName + "/" + clientId;
        
        try {
            // Get current secrets from Vault
            JSONObject currentSecrets = getCurrentSecretsFromVault(vaultPath);
            JSONObject secretsObj;
            
            if (currentSecrets == null) {
                // No secrets exist yet, create new object
                secretsObj = new JSONObject();
            } else {
                // Extract existing secrets
                secretsObj = currentSecrets.optJSONObject(SECRETS_FIELD);
                if (secretsObj == null) {
                    secretsObj = new JSONObject();
                }
            }
            
            // Generate unique ID for this secret
            String secretId = UUID.randomUUID().toString();
            
            // Add the new secret
            JSONObject secretData = new JSONObject();
            secretData.put("value", secret);
            secretData.put(CREATED_FIELD, System.currentTimeMillis() / 1000);
            secretsObj.put(secretId, secretData);
            
            // Create the final payload
            JSONObject payload = new JSONObject();
            JSONObject data = new JSONObject();
            data.put(ACTIVE_SECRET_FIELD, secretId);
            data.put(SECRETS_FIELD, secretsObj);
            payload.put("data", data);
            
            // Store in Vault
            HttpPost request = new HttpPost(vaultUrl + "/v1/" + vaultPath);
            request.addHeader("X-Vault-Token", vaultToken);
            request.addHeader("Content-Type", "application/json");
            request.setEntity(new StringEntity(payload.toString()));
            
            HttpResponse response = httpClient.execute(request);
            int statusCode = response.getStatusLine().getStatusCode();
            
            if (statusCode != 200 && statusCode != 204) {
                HttpEntity entity = response.getEntity();
                String responseBody = entity != null ? EntityUtils.toString(entity) : null;
                logger.errorf("Failed to store client secret in Vault. Status code: %d, Response: %s", 
                        statusCode, responseBody);
                return false;
            }
            
            logger.infof("Successfully stored client secret in Vault at path '%s'", vaultPath);
            return true;
            
        } catch (IOException | JSONException e) {
            logger.errorf("Error storing client secret in Vault: %s", e.getMessage());
            return false;
        }
    }
    
    /**
     * Retrieves a client secret from Vault
     * @param realmName The realm name
     * @param clientId The client ID
     * @return The client secret, or null if not found
     */
    public String getClientSecretFromVault(String realmName, String clientId) {
        String vaultPath = secretsBasePath + "/" + realmName + "/" + clientId;
        
        try {
            // Get current secrets from Vault
            JSONObject data = getCurrentSecretsFromVault(vaultPath);
            if (data == null) {
                logger.errorf("No data found in Vault at path '%s'", vaultPath);
                return null;
            }
            
            // Get active secret ID
            String activeSecretId = data.optString(ACTIVE_SECRET_FIELD);
            if (activeSecretId == null || activeSecretId.isEmpty()) {
                logger.errorf("No active secret ID found in Vault at path '%s'", vaultPath);
                return null;
            }
            
            // Get secrets object
            JSONObject secretsObj = data.optJSONObject(SECRETS_FIELD);
            if (secretsObj == null) {
                logger.errorf("No secrets object found in Vault at path '%s'", vaultPath);
                return null;
            }
            
            // Get active secret
            JSONObject secretData = secretsObj.optJSONObject(activeSecretId);
            if (secretData == null) {
                logger.errorf("Active secret with ID '%s' not found in Vault at path '%s'", activeSecretId, vaultPath);
                return null;
            }
            
            // Get secret value
            String secretValue = secretData.optString("value");
            if (secretValue == null || secretValue.isEmpty()) {
                logger.errorf("No value found for active secret with ID '%s' in Vault at path '%s'", activeSecretId, vaultPath);
                return null;
            }
            
            return secretValue;
            
        } catch (Exception e) {
            logger.errorf("Error retrieving client secret from Vault: %s", e.getMessage());
            return null;
        }
    }
    
    /**
     * Gets the current secrets data from Vault
     * @param vaultPath The path in Vault to get the secrets from
     * @return The secrets data JSON object, or null if not found
     */
    private JSONObject getCurrentSecretsFromVault(String vaultPath) {
        try {
            // Create request to Vault
            HttpGet request = new HttpGet(vaultUrl + "/v1/" + vaultPath);
            request.addHeader("X-Vault-Token", vaultToken);
            
            // Execute request
            HttpResponse response = httpClient.execute(request);
            int statusCode = response.getStatusLine().getStatusCode();
            
            if (statusCode == 404) {
                // No secrets exist yet
                return null;
            }
            
            if (statusCode != 200) {
                logger.errorf("Failed to get secrets from Vault. Status code: %d", statusCode);
                return null;
            }
            
            // Parse response
            HttpEntity entity = response.getEntity();
            String responseBody = EntityUtils.toString(entity);
            JSONObject jsonResponse = new JSONObject(responseBody);
            
            // Get data object
            return jsonResponse.getJSONObject("data").getJSONObject("data");
            
        } catch (IOException | JSONException e) {
            logger.errorf("Error getting secrets from Vault: %s", e.getMessage());
            return null;
        }
    }
    
    @Override
    public void close() {
        // Close any resources if needed
    }
} 