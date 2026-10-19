package in.hostelcc;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

@Component
public class CodeMailer {
    private final JavaMailSender sender; private final String from;
    public CodeMailer(JavaMailSender sender,@Value("${app.mail-from}") String from) { this.sender=sender; this.from=from; }
    public void send(String email,String code) {
        var message=new SimpleMailMessage(); message.setFrom(from); message.setTo(email);
        message.setSubject("Your HostelCC sign-in code");
        message.setText("Your HostelCC sign-in code is "+code+". It expires in 10 minutes and can be used once. If you did not request this, ignore this email.");
        sender.send(message);
    }
}
