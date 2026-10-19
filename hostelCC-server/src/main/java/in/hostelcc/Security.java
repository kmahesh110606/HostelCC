package in.hostelcc;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.csrf.*;
import org.springframework.web.cors.*;
import org.springframework.web.filter.OncePerRequestFilter;
import com.nimbusds.jose.jwk.source.ImmutableSecret;
import static in.hostelcc.Store.*;

@Configuration
public class Security {
    @Bean SecretKeySpec signingKey(@Value("${app.jwt-secret}") String secret) {
        if(secret.getBytes(StandardCharsets.UTF_8).length<32) throw new IllegalStateException("JWT_SECRET must contain at least 32 random bytes");
        return new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256");
    }
    @Bean JwtEncoder jwtEncoder(SecretKeySpec key) { return new NimbusJwtEncoder(new ImmutableSecret<>(key)); }
    @Bean JwtDecoder jwtDecoder(SecretKeySpec key) {
        var decoder=NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
        decoder.setJwtValidator(JwtValidators.createDefaultWithIssuer("hostelcc")); return decoder;
    }
    @Bean SecurityFilterChain filterChain(HttpSecurity http,JwtDecoder decoder,Store db,
            @Value("${app.allowed-origins}") String origins,@Value("${app.cookie-secure}") boolean secure) throws Exception {
        var csrf=new CookieCsrfTokenRepository();
        csrf.setCookieCustomizer(c->c.path("/").sameSite("Lax").secure(secure).httpOnly(true));
        var cors=new CorsConfiguration(); cors.setAllowedOrigins(Arrays.asList(origins.split(",")));
        cors.setAllowedMethods(List.of("GET","POST","PUT","PATCH","OPTIONS"));
        cors.setAllowedHeaders(List.of("Content-Type","X-XSRF-TOKEN")); cors.setAllowCredentials(true);
        var source=new UrlBasedCorsConfigurationSource(); source.registerCorsConfiguration("/api/**",cors);
        http.cors(c->c.configurationSource(source))
            .csrf(c->c.csrfTokenRepository(csrf).csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler()))
            .sessionManagement(c->c.sessionCreationPolicy(SessionCreationPolicy.STATELESS).sessionAuthenticationStrategy(new org.springframework.security.web.authentication.session.NullAuthenticatedSessionStrategy()))
            .formLogin(c->c.disable()).httpBasic(c->c.disable()).logout(c->c.disable())
            .authorizeHttpRequests(c->c.dispatcherTypeMatchers(DispatcherType.ASYNC).permitAll().requestMatchers("/api/auth/csrf","/api/auth/request-code","/api/auth/verify-code","/api/health").permitAll().anyRequest().authenticated())
            .exceptionHandling(c->c.authenticationEntryPoint((req,res,e)->jsonError(res,401,"Sign in to continue"))
                .accessDeniedHandler((req,res,e)->jsonError(res,403,"Access denied or CSRF token expired")))
            .addFilterBefore(new OncePerRequestFilter() {
                @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain) throws ServletException,IOException {
                    String token=null;
                    if(req.getCookies()!=null) for(var cookie:req.getCookies()) if(cookie.getName().equals("HOSTELCC_SESSION")) token=cookie.getValue();
                    if(token!=null) try {
                        var jwt=decoder.decode(token);
                        var rows=db.list("SELECT u.*,s.id AS session_id FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.id=? AND s.user_id=? AND s.revoked=false AND u.active=true AND s.expires_at>?",jwt.getId(),jwt.getSubject(),now());
                        if(!rows.isEmpty()) {
                            var u=rows.getFirst(); var blocks=new HashSet<String>();
                            var scopes=db.list("SELECT book,target_id FROM duty_scopes WHERE user_id=? AND active=true",str(u,"id")).stream().map(g->new Actor.Grant(str(g,"book"),str(g,"targetId"))).toList();
                            for(var grant:scopes) {
                                if(List.of("HOSTEL","OUTINGS","DISCIPLINE","MAINTENANCE").contains(grant.book())) blocks.add(grant.targetId());
                                if(grant.book().equals("MESS")) db.list("SELECT block_id FROM mess_blocks WHERE mess_id=?",grant.targetId()).forEach(b->blocks.add(str(b,"blockId")));
                                if(grant.book().equals("CLOAKROOM")) db.list("SELECT block_id FROM storage_rooms WHERE id=?",grant.targetId()).forEach(b->blocks.add(str(b,"blockId")));
                            }
                            if(!str(u,"blockId").isBlank()) blocks.add(str(u,"blockId"));
                            var actor=new Actor(str(u,"id"),str(u,"role"),str(u,"blockId"),str(u,"messId"),Set.copyOf(blocks),jwt.getId(),scopes);
                            SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(actor,null,List.of()));
                        }
                    } catch(JwtException|IllegalArgumentException ignored) { /* Invalid cookies never establish identity. */ }
                    chain.doFilter(req,res);
                }
            },UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
    static void jsonError(HttpServletResponse res,int code,String message) throws IOException {
        res.setStatus(code); res.setContentType("application/json"); res.getWriter().write("{\"message\":\""+message+"\"}");
    }
}
