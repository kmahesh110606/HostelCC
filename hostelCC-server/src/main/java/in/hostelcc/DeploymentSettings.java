package in.hostelcc;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;

/** Fail closed when a deployment accidentally uses development settings. */
@Configuration
@Profile("!dev & !test")
public class DeploymentSettings {
    public DeploymentSettings(Environment env) {
        require(env.getProperty("spring.datasource.url", "").startsWith("jdbc:postgresql:"), "DB_URL must be a PostgreSQL JDBC URL");
        require(Boolean.parseBoolean(env.getProperty("app.cookie-secure", "false")), "COOKIE_SECURE must be true outside the dev profile");
        String secret=env.getProperty("app.jwt-secret", "");
        require(secret.length()>=32 && !secret.startsWith("replace-") && !secret.contains("development-only") && !secret.startsWith("test-only"), "Provide a randomly generated JWT_SECRET");
        String origins=env.getProperty("app.allowed-origins", "");
        require(!origins.isBlank() && java.util.Arrays.stream(origins.split(",")).allMatch(s->s.startsWith("https://")&&!s.contains("*")), "ALLOWED_ORIGINS must list explicit HTTPS origins");
        require(!java.util.List.of("localhost","mailpit","").contains(env.getProperty("spring.mail.host", "localhost")), "Set SMTP_HOST to your mail provider");
        require(Boolean.parseBoolean(env.getProperty("spring.mail.properties.mail.smtp.starttls.required", "false")), "SMTP_STARTTLS must be true for deployment");
    }
    private static void require(boolean valid,String message) {
        if(!valid) throw new IllegalStateException(message);
    }
}
