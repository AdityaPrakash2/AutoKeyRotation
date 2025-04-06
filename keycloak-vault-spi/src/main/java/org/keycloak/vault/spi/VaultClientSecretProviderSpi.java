package org.keycloak.vault.spi;

import org.keycloak.provider.Provider;
import org.keycloak.provider.ProviderFactory;
import org.keycloak.provider.Spi;

/**
 * SPI interface for the Vault client secret provider.
 */
public class VaultClientSecretProviderSpi implements Spi {
    
    @Override
    public boolean isInternal() {
        return false;
    }
    
    @Override
    public String getName() {
        return "vault-client-secret";
    }
    
    @Override
    public Class<? extends Provider> getProviderClass() {
        return VaultClientSecretProvider.class;
    }
    
    @Override
    public Class<? extends ProviderFactory> getProviderFactoryClass() {
        return VaultClientSecretProviderFactory.class;
    }
} 