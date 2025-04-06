package org.keycloak.vault.spi;

import org.keycloak.component.ComponentModel;

/**
 * Configuration for the Vault client secret provider.
 */
public class VaultClientSecretProviderConfig {
    
    // Configuration property names
    public static final String VAULT_URL = "vaultUrl";
    public static final String VAULT_TOKEN = "vaultToken";
    public static final String SECRETS_BASE_PATH = "secretsBasePath";
    
    // Default values
    private static final String DEFAULT_SECRETS_BASE_PATH = "secret/data/keycloak/client-secrets";
    
    private final ComponentModel model;
    
    public VaultClientSecretProviderConfig(ComponentModel model) {
        this.model = model;
    }
    
    /**
     * Get a configuration value
     * @param key The configuration key
     * @return The configuration value
     */
    protected String get(String key) {
        return model != null ? model.get(key) : null;
    }
    
    /**
     * Get a configuration value as an integer
     * @param key The configuration key
     * @param defaultValue The default value if not found
     * @return The configuration value as an integer
     */
    protected int getInt(String key, int defaultValue) {
        String value = get(key);
        if (value == null) return defaultValue;
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }
    
    public String getVaultUrl() {
        String configuredUrl = get(VAULT_URL);
        return configuredUrl != null ? configuredUrl : System.getenv("KC_VAULT_URL");
    }
    
    public String getVaultToken() {
        String configuredToken = get(VAULT_TOKEN);
        return configuredToken != null ? configuredToken : System.getenv("KC_VAULT_TOKEN");
    }
    
    public String getSecretsBasePath() {
        String configuredPath = get(SECRETS_BASE_PATH);
        return configuredPath != null ? configuredPath : 
               System.getenv("KC_CLIENT_SECRETS_PATH") != null ?
               System.getenv("KC_CLIENT_SECRETS_PATH") : DEFAULT_SECRETS_BASE_PATH;
    }
} 