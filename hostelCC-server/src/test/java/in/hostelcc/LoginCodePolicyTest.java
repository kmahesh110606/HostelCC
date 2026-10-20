package in.hostelcc;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import static org.junit.jupiter.api.Assertions.*;

class LoginCodePolicyTest {
    @Test void fixedCodeRequiresExplicitDevelopmentMode() {
        var env = new MockEnvironment().withProperty("app.development-otp", "110606");
        assertThrows(IllegalStateException.class, () -> new LoginCodePolicy(env));
        env.setActiveProfiles("dev");
        var policy = new LoginCodePolicy(env);
        assertTrue(policy.development());
        assertEquals("110606", policy.next());
        env.setProperty("app.development-otp", "bad");
        assertThrows(IllegalStateException.class, () -> new LoginCodePolicy(env));
    }
    @Test void defaultUsesEmailCodes() {
        var policy = new LoginCodePolicy(new MockEnvironment());
        assertFalse(policy.development());
        assertTrue(policy.next().matches("[0-9]{6}"));
    }
}
