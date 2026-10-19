package in.hostelcc;

import jakarta.servlet.http.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class AuthController {
    private final AuthService auth; private final Store db; private final boolean secure;
    public AuthController(AuthService auth,Store db,@Value("${app.cookie-secure}") boolean secure) { this.auth=auth;this.db=db;this.secure=secure; }
    record EmailRequest(@NotBlank @Email @Size(max=254) String email) {}
    record Verify(@NotBlank @Email @Size(max=254) String email,@NotBlank @Pattern(regexp="[0-9]{6}") String code,Boolean remember) {}
    @GetMapping("/health") ResponseEntity<Map<String,String>> health() {
        try { db.count("SELECT count(*) FROM otp_guard"); return ResponseEntity.ok(Map.of("status","ok")); }
        catch(org.springframework.dao.DataAccessException e) { return ResponseEntity.status(503).body(Map.of("status","unavailable")); }
    }
    @GetMapping("/auth/csrf") Map<String,String> csrf(CsrfToken token) { return Map.of("token",token.getToken()); }
    @PostMapping("/auth/request-code") Map<String,String> request(@Valid @RequestBody EmailRequest body,HttpServletRequest req) {
        auth.request(body.email().strip().toLowerCase(java.util.Locale.ROOT),req.getRemoteAddr());
        return Map.of("message","If your email is registered, a code has been sent. Check your inbox.");
    }
    @PostMapping("/auth/verify-code") Map<String,Object> verify(@Valid @RequestBody Verify body,HttpServletResponse res) {
        var login=auth.verify(body.email().strip().toLowerCase(java.util.Locale.ROOT),body.code(),Boolean.TRUE.equals(body.remember()));
        var cookie=ResponseCookie.from("HOSTELCC_SESSION",login.token()).httpOnly(true).secure(secure).sameSite("Lax").path("/");
        if(Boolean.TRUE.equals(body.remember())) cookie.maxAge(Duration.ofSeconds(login.seconds()));
        res.addHeader(HttpHeaders.SET_COOKIE,cookie.build().toString()); return login.user();
    }
    @GetMapping("/auth/me") Map<String,Object> me(@AuthenticationPrincipal Actor actor) { return auth.profile(actor.id()); }
    @PostMapping("/auth/logout") Map<String,String> logout(@AuthenticationPrincipal Actor actor,HttpServletResponse res) {
        db.exec("UPDATE sessions SET revoked=true WHERE id=?",actor.sessionId());
        res.addHeader(HttpHeaders.SET_COOKIE,ResponseCookie.from("HOSTELCC_SESSION","").httpOnly(true).secure(secure).sameSite("Lax").path("/").maxAge(0).build().toString());
        return Map.of("message","Signed out");
    }
}
