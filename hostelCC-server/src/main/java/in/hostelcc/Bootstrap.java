package in.hostelcc;

import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.support.TransactionTemplate;
import static in.hostelcc.Store.*;

@Configuration
public class Bootstrap {
    @Bean ApplicationRunner administrator(Store db,TransactionTemplate transaction,@Value("${app.admin-email}") String email,@Value("${app.bootstrap-required:true}") boolean required) {
        return args->{
            transaction.executeWithoutResult(status->{
                db.one("SELECT id FROM otp_guard WHERE id=1 FOR UPDATE");
                if(db.count("SELECT count(*) FROM users")==0) {
                    String normalized=email.strip().toLowerCase(java.util.Locale.ROOT);
                    if(normalized.isBlank() && !required) return;
                    if(!normalized.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) throw new IllegalStateException("Set ADMIN_EMAIL to the first administrator's email address");
                    db.exec("INSERT INTO users(id,email,name,role,created_at) VALUES(?,?,?,?,?)",id(),normalized,"Administrator","ADMIN",now());
                }
            });
        };
    }
}
