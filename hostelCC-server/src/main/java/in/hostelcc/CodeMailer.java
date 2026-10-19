package in.hostelcc;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

@Component
public class CodeMailer {
    private static final Logger log = LoggerFactory.getLogger(CodeMailer.class);
    private final JavaMailSender sender;
    private final String from;

    public CodeMailer(@Autowired(required = false) JavaMailSender sender,
                      @Value("${app.mail-from:hostelcc@localhost}") String from) {
        this.sender = sender;
        this.from = from;
    }

    public void send(String email, String code) {
        log.info("HostelCC sign-in OTP for {}: {}", email, code);
        if (sender != null) {
            try {
                var message = new SimpleMailMessage();
                message.setFrom(from);
                message.setTo(email);
                message.setSubject("Your HostelCC sign-in code");
                message.setText("Your HostelCC sign-in code is " + code + ". It expires in 10 minutes and can be used once. If you did not request this, ignore this email.");
                sender.send(message);
            } catch (org.springframework.mail.MailException e) {
                log.warn("Email delivery skipped or mail server unavailable: {}", e.getMessage());
            }
        }
    }
}
