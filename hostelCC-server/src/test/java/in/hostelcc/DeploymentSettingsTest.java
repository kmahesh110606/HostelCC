package in.hostelcc;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;

class DeploymentSettingsTest {
    MockEnvironment settings() {
        return new MockEnvironment()
            .withProperty("spring.datasource.url","jdbc:postgresql://db:5432/hostelcc")
            .withProperty("app.cookie-secure","true")
            .withProperty("app.jwt-secret","9ddf24b2f7b408a23771ad602eb70eb7208ec79a2e466a14")
            .withProperty("app.allowed-origins","https://hostel.example.edu")
            .withProperty("spring.mail.host","smtp.example.edu")
            .withProperty("spring.mail.properties.mail.smtp.starttls.required","true");
    }
    @Test void productionCannotUseDevelopmentSettings() {
        assertDoesNotThrow(()->new DeploymentSettings(settings()));
        for(var change:java.util.Map.of(
            "spring.datasource.url","jdbc:h2:mem:example",
            "app.cookie-secure","false",
            "app.jwt-secret","replace-with-at-least-32-random-bytes",
            "app.allowed-origins","http://localhost:5173",
            "spring.mail.host","test-smtp",
            "spring.mail.properties.mail.smtp.starttls.required","false").entrySet()) {
            assertThrows(IllegalStateException.class,()->new DeploymentSettings(settings().withProperty(change.getKey(),change.getValue())),change.getKey());
        }
    }
}
