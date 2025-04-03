package org.keycloak.vault.spi;

import org.keycloak.component.ComponentModel;
import org.keycloak.component.ComponentValidationException;
import org.keycloak.keys.AbstractRsaKeyProviderFactory;
import org.keycloak.keys.KeyProvider;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.List;

/**
 * Factory for creating VaultKeyProvider instances.
 */
public class VaultKeyProviderFactory extends AbstractRsaKeyProviderFactory {

    public static final String ID = "vault";

    @Override
    public KeyProvider create(KeycloakSession session, ComponentModel model) {
        return new VaultKeyProvider(session, this, new VaultKeyProviderConfig(model));
    }

    @Override
    public String getId() {
        return ID;
    }

    @Override
    public String getHelpText() {
        return "Provides keys stored in HashiCorp Vault";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        List<ProviderConfigProperty> properties = super.getConfigProperties();
        
        // Add Vault-specific configuration properties
        ProviderConfigProperty vaultUrl = new ProviderConfigProperty(
                VaultKeyProviderConfig.VAULT_URL,
                "Vault URL",
                "URL of the Vault server (e.g., http://vault:8201)",
                ProviderConfigProperty.STRING_TYPE,
                null
        );
        
        ProviderConfigProperty vaultToken = new ProviderConfigProperty(
                VaultKeyProviderConfig.VAULT_TOKEN,
                "Vault Token",
                "Token for authenticating with Vault",
                ProviderConfigProperty.STRING_TYPE,
                null
        );
        
        ProviderConfigProperty keyPath = new ProviderConfigProperty(
                VaultKeyProviderConfig.KEY_PATH,
                "Key Path",
                "Path to the keys in Vault (e.g., secret/data/keycloak/keys/signing)",
                ProviderConfigProperty.STRING_TYPE,
                null
        );
        
        ProviderConfigProperty minRefreshSeconds = new ProviderConfigProperty(
                VaultKeyProviderConfig.MIN_REFRESH_SECONDS,
                "Minimum Refresh Seconds",
                "Minimum time in seconds between key refreshes",
                ProviderConfigProperty.STRING_TYPE,
                "60"
        );
        
        properties.add(vaultUrl);
        properties.add(vaultToken);
        properties.add(keyPath);
        properties.add(minRefreshSeconds);
        
        return properties;
    }
    
    @Override
    public void validateConfiguration(KeycloakSession session, ComponentModel model) throws ComponentValidationException {
        super.validateConfiguration(session, model);

        VaultKeyProviderConfig config = new VaultKeyProviderConfig(model);
        
        if (config.getVaultUrl() == null || config.getVaultUrl().trim().isEmpty()) {
            throw new ComponentValidationException("Vault URL must be specified");
        }
        
        if (config.getVaultToken() == null || config.getVaultToken().trim().isEmpty()) {
            throw new ComponentValidationException("Vault Token must be specified");
        }
        
        if (config.getKeyPath() == null || config.getKeyPath().trim().isEmpty()) {
            throw new ComponentValidationException("Key Path must be specified");
        }
    }

    @Override
    public String getDisplayType() {
        return "Vault Key Provider";
    }
} 