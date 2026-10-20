package in.hostelcc;

import java.security.SecureRandom;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

@Component
public class LoginCodePolicy {
    private final SecureRandom random = new SecureRandom();
    private final String fixed;
    public LoginCodePolicy(Environment env) {
        fixed = env.getProperty("app.development-otp", "").trim();
        if (!fixed.isEmpty() && (!env.acceptsProfiles(Profiles.of("dev")) || !fixed.matches("[0-9]{6}")))
            throw new IllegalStateException("DEV_LOGIN_OTP requires the dev profile and exactly six digits");
    }
    public boolean development() { return !fixed.isEmpty(); }
    public String next() { return development() ? fixed : String.format("%06d", random.nextInt(1000000)); }
}
