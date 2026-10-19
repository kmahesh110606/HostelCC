package in.hostelcc;

import java.time.*;
import java.security.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.web.server.ResponseStatusException;
import static in.hostelcc.Store.*;

@Service
public class AuthService {
    private final Store db; private final CodeMailer mailer; private final SecretKeySpec key; private final JwtEncoder encoder;
    private final SecureRandom random=new SecureRandom();
    @Value("${app.otp-ip-limit:300}") int ipLimit;
    public AuthService(Store db,CodeMailer mailer,SecretKeySpec key,JwtEncoder encoder) { this.db=db;this.mailer=mailer;this.key=key;this.encoder=encoder; }
    String hash(String value) {
        try { var mac=Mac.getInstance("HmacSHA256"); mac.init(key); return HexFormat.of().formatHex(mac.doFinal(value.getBytes(StandardCharsets.UTF_8))); }
        catch(GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    @Transactional(noRollbackFor=ResponseStatusException.class)
    public void request(String email,String ip) {
        db.one("SELECT id FROM otp_guard WHERE id=1 FOR UPDATE");
        String since=Instant.now().minusSeconds(3600).toString(), mailHash=hash(email),ipHash=hash(ip);
        if(db.count("SELECT count(*) FROM otp_requests WHERE email_hash=? AND requested_at>?",mailHash,since)>=5 ||
           db.count("SELECT count(*) FROM otp_requests WHERE ip_hash=? AND requested_at>?",ipHash,since)>=ipLimit ||
           db.count("SELECT count(*) FROM otp_requests WHERE email_hash=? AND requested_at>?",mailHash,Instant.now().minusSeconds(60).toString())>0)
            throw error(429,"Please wait before requesting another code");
        db.exec("INSERT INTO otp_requests VALUES(?,?,?,?)",id(),mailHash,ipHash,now());
        db.exec("DELETE FROM otp_requests WHERE requested_at<?",Instant.now().minusSeconds(86400).toString());
        var users=db.list("SELECT id,email FROM users WHERE email=? AND active=true",email);
        if(users.isEmpty()) return;
        var user=users.getFirst(); String uid=str(user,"id"),code=String.format("%06d",random.nextInt(1000000));
        db.exec("DELETE FROM otp_challenges WHERE user_id=?",uid);
        db.exec("INSERT INTO otp_challenges(user_id,code_hash,expires_at,attempts,consumed) VALUES(?,?,?,0,false)",uid,hash(uid+":"+code),Instant.now().plusSeconds(600).toString());
        try { mailer.send(email,code); }
        catch(org.springframework.mail.MailException e) { throw error(503,"Email delivery is unavailable. Please try again later."); }
    }
    public record Login(String token,long seconds,Map<String,Object> user) {}
    @Transactional(noRollbackFor=ResponseStatusException.class)
    public Login verify(String email,String code,boolean remember) {
        var rows=db.list("SELECT o.*,u.active FROM otp_challenges o JOIN users u ON u.id=o.user_id WHERE u.email=? FOR UPDATE",email);
        if(rows.isEmpty()) throw error(400,"Invalid or expired code");
        var row=rows.getFirst(); String uid=str(row,"userId");
        if(!bool(row,"active") || bool(row,"consumed") || ((Number)row.get("attempts")).intValue()>=5 || !Instant.parse(str(row,"expiresAt")).isAfter(Instant.now())) throw error(400,"Invalid or expired code");
        db.exec("UPDATE otp_challenges SET attempts=attempts+1 WHERE user_id=?",uid);
        if(!MessageDigest.isEqual(hash(uid+":"+code).getBytes(StandardCharsets.UTF_8),str(row,"codeHash").getBytes(StandardCharsets.UTF_8))) throw error(400,"Invalid or expired code");
        db.exec("UPDATE otp_challenges SET consumed=true WHERE user_id=?",uid);
        String sid=id(); long seconds=remember?2592000:43200; Instant expiry=Instant.now().plusSeconds(seconds);
        db.exec("INSERT INTO sessions(id,user_id,expires_at,revoked) VALUES(?,?,?,false)",sid,uid,expiry.toString());
        var claims=JwtClaimsSet.builder().issuer("hostelcc").subject(uid).id(sid).issuedAt(Instant.now()).expiresAt(expiry).build();
        String token=encoder.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(),claims)).getTokenValue();
        return new Login(token,seconds,profile(uid));
    }
    public Map<String,Object> profile(String uid) {
        var user=db.one("SELECT u.*,b.name AS block_name,r.number AS room_number,m.name AS mess_name FROM users u LEFT JOIN blocks b ON b.id=u.block_id LEFT JOIN rooms r ON r.id=u.room_id LEFT JOIN messes m ON m.id=u.mess_id WHERE u.id=?",uid);
        user.put("scopes",db.list("SELECT * FROM duty_scopes WHERE user_id=? AND active=true",uid)); return user;
    }
}
