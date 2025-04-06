package org.keycloak.vault.spi;

import java.util.List;

import org.jboss.logging.Logger;
import org.keycloak.Config;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.provider.ProviderConfigurationBuilder;
import org.keycloak.provider.ProviderFactory;

/**
 * Factory for creating VaultClientSecretProvider instances.
 */
public class VaultClientSecretProviderFactory implements ProviderFactory<VaultClientSecretProvider> {
    private static final Logger logger = Logger.getLogger(VaultClientSecretProviderFactory.class);
    
    public static final String ID = "vault-client-secret";
    
    private static final String HELP_TEXT = "Client Secret Provider which uses HashiCorp Vault for storage and rotation";
    
    @Override
    public VaultClientSecretProvider create(KeycloakSession session) {
        VaultClientSecretProviderConfig config = new VaultClientSecretProviderConfig(null);
        return new VaultClientSecretProvider(session, config);
    }
    
    @Override
    public void init(Config.Scope config) {
        logger.info("Initializing VaultClientSecretProviderFactory");
    }
    
    @Override
    public void postInit(KeycloakSessionFactory factory) {
        logger.info("VaultClientSecretProviderFactory initialized");
    }
    
    @Override
    public void close() {
        logger.info("Closing VaultClientSecretProviderFactory");
    }
    
    @Override
    public String getId() {
        return ID;
    }
    
    public List<ProviderConfigProperty> getConfigProperties() {
        return ProviderConfigurationBuilder.create()
                .property()
                .name(VaultClientSecretProviderConfig.VAULT_URL)
                .type(ProviderConfigProperty.STRING_TYPE)
                .label("Vault URL")
                .defaultValue("http://vault:8201")
                .helpText("URL of the Vault server")
                .add()
                .property()
                .name(VaultClientSecretProviderConfig.VAULT_TOKEN)
                .type(ProviderConfigProperty.PASSWORD)
                .label("Vault Token")
                .helpText("Token used to authenticate with Vault")
                .add()
                .property()
                .name(VaultClientSecretProviderConfig.SECRETS_BASE_PATH)
                .type(ProviderConfigProperty.STRING_TYPE)
                .label("Secrets Base Path")
                .defaultValue("secret/data/keycloak/client-secrets")
                .helpText("Base path in Vault where client secrets are stored")
                .add()
                .build();
    }
} 