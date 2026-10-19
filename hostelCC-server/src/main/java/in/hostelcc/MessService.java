package in.hostelcc;

import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class MessService {
    final Store db; final DirectoryService directory;
    public MessService(Store db,DirectoryService directory) { this.db=db;this.directory=directory; }
    @Transactional
    public String menu(Actor a,Map<String,Object> b) {
        String mess=required(b,"messId",64); directory.manageMess(a,mess);
        db.one("SELECT id FROM messes WHERE id=? AND active=true FOR UPDATE",mess);
        String day=choice(b,"day","MON","TUE","WED","THU","FRI","SAT","SUN"),breakfast=required(b,"breakfast",4000),lunch=required(b,"lunch",4000),snacks=required(b,"snacks",4000),dinner=required(b,"dinner",4000);
        var old=db.list("SELECT * FROM menus WHERE mess_id=? AND weekday=?",mess,day); String id=old.isEmpty()?id():str(old.getFirst(),"id");
        if(old.isEmpty()) db.exec("INSERT INTO menus VALUES(?,?,?,?,?,?,?,?)",id,mess,day,breakfast,lunch,snacks,dinner,now());
        else {
            db.audit(a,"ARCHIVE_MENU","menus",id,null,old.getFirst().toString());
            db.exec("UPDATE menus SET breakfast=?,lunch=?,snacks=?,dinner=?,updated_at=? WHERE id=?",breakfast,lunch,snacks,dinner,now(),id);
        }
        db.audit(a,"SAVE_MENU","menus",id,null,day); return id;
    }
    @Transactional
    public String feedback(Actor a,Map<String,Object> b) {
        a.require("STUDENT"); var student=directory.student(a.id()); String mess=str(student,"messId");
        if(mess.isBlank()) throw error(409,"Ask an administrator to assign your mess first");
        String meal=choice(b,"meal","BREAKFAST","LUNCH","SNACKS","DINNER"),date=required(b,"mealDate",10); int rating=integer(b,"rating",1,5);
        try { LocalDate d=LocalDate.parse(date),today=LocalDate.now(ZoneId.of("Asia/Kolkata")); if(d.isAfter(today)||d.isBefore(today.minusDays(7))) throw error(400,"Feedback is accepted for the past seven days"); }
        catch(java.time.DateTimeException e) { throw error(400,"Enter a valid meal date"); }
        String id=id(); db.exec("INSERT INTO feedback(id,student_id,block_id,mess_id,meal,meal_date,rating,comment,created_at) VALUES(?,?,?,?,?,?,?,?,?)",id,a.id(),a.blockId(),mess,meal,date,rating,optional(b,"comment",4000),now()); return id;
    }
    @Transactional
    public void reply(Actor a,String id,Map<String,Object> b) {
        var row=db.one("SELECT * FROM feedback WHERE id=? FOR UPDATE",id); directory.manageMess(a,str(row,"messId"));
        String reply=required(b,"reply",2000); db.exec("UPDATE feedback SET reply=? WHERE id=?",reply,id);
        db.audit(a,"REPLY_FEEDBACK","feedback",id,str(row,"blockId"),reply);
    }
    @Transactional
    public String poll(Actor a,Map<String,Object> b) {
        String mess=required(b,"messId",64); directory.manageMess(a,mess);
        db.one("SELECT id FROM messes WHERE id=? AND active=true",mess);
        String title=required(b,"title",200),closes=instant(b,"closesAt");
        if(!Instant.parse(closes).isAfter(Instant.now())) throw error(400,"Poll closing time must be in the future");
        var options=DirectoryService.ids(b,"options"); if(options.size()<2 || options.size()>10 || options.stream().anyMatch(o->o.length()>140)) throw error(400,"Provide 2 to 10 distinct options of at most 140 characters");
        String id=id(); db.exec("INSERT INTO polls(id,mess_id,title,closes_at,created_at) VALUES(?,?,?,?,?)",id,mess,title,closes,now());
        for(String option:options) db.exec("INSERT INTO poll_options VALUES(?,?,?)",id(),id,option);
        db.audit(a,"CREATE_POLL","polls",id,null,title); return id;
    }
    @Transactional
    public void vote(Actor a,String id,Map<String,Object> b) {
        a.require("STUDENT"); var poll=db.one("SELECT * FROM polls WHERE id=? FOR UPDATE",id); directory.mess(a,str(poll,"messId"));
        if(!bool(poll,"enabled") || !Instant.parse(str(poll,"closesAt")).isAfter(Instant.now())) throw error(409,"This poll is closed");
        String option=required(b,"optionId",64); db.one("SELECT id FROM poll_options WHERE id=? AND poll_id=?",option,id);
        db.exec("INSERT INTO votes VALUES(?,?,?,?,?)",id,a.id(),option,a.blockId(),now());
    }
    @Transactional
    public String change(Actor a,Map<String,Object> b) {
        a.require("STUDENT"); var u=db.one("SELECT * FROM users WHERE id=? FOR UPDATE",a.id());
        if(!bool(u,"messChangeAccess")) throw error(403,"An administrator must open mess changes for you");
        String target=required(b,"messId",64); if(target.equals(a.messId())) throw error(400,"Choose a different mess");
        directory.assignMess(a.id(),target,a.blockId());
        if(db.count("SELECT count(*) FROM mess_changes WHERE student_id=? AND status='PENDING'",a.id())>0) throw error(409,"A mess change request is already pending");
        String id=id(); db.exec("INSERT INTO mess_changes(id,student_id,block_id,mess_id,status,created_at) VALUES(?,?,?,?,'PENDING',?)",id,a.id(),a.blockId(),target,now()); return id;
    }
    @Transactional
    public void decideChange(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN"); var row=db.one("SELECT * FROM mess_changes WHERE id=? FOR UPDATE",id);
        if(!str(row,"status").equals("PENDING")) throw error(409,"This request has already been decided");
        String action=choice(b,"action","approve","reject"),note=optional(b,"note",2000);
        if(action.equals("approve")) {
            var student=directory.student(str(row,"studentId")); db.one("SELECT id FROM users WHERE id=? FOR UPDATE",str(row,"studentId"));
            directory.assignMess(str(row,"studentId"),str(row,"messId"),str(student,"blockId"));
            db.exec("UPDATE users SET mess_id=?,mess_change_access=false WHERE id=?",str(row,"messId"),str(row,"studentId"));
        }
        db.exec("UPDATE mess_changes SET status=?,decision_note=? WHERE id=?",action.equals("approve")?"APPROVED":"REJECTED",note,id);
        db.audit(a,"MESS_CHANGE_"+action.toUpperCase(Locale.ROOT),"messChanges",id,str(row,"blockId"),note);
    }
    @Transactional
    public String announcement(Actor a,String id,Map<String,Object> b) {
        a.require("ADMIN","WARDEN","SUPERVISOR"); String block=optional(b,"blockId",64),audience=choice(b,"audience","ALL","STUDENT","ADMIN","DIRECTOR","WARDEN","SUPERVISOR","MESS_MANAGER","HOUSEKEEPING");
        if(!a.is("ADMIN") && block.isBlank()) throw error(403,"Select one of your assigned blocks");
        if(!block.isBlank()) { a.duty("HOSTEL",block); db.one("SELECT id FROM blocks WHERE id=?",block); }
        String title=required(b,"title",140),body=required(b,"body",10000),level=choice(b,"level","INFO","WARNING","URGENT");
        if(id==null) { id=id(); db.exec("INSERT INTO announcements(id,title,body,level,audience,block_id,created_by,created_at) VALUES(?,?,?,?,?,?,?,?)",id,title,body,level,audience,DirectoryService.nullable(block),a.id(),now()); }
        else {
            var old=db.one("SELECT * FROM announcements WHERE id=? FOR UPDATE",id);
            if(!a.is("ADMIN")) { if(str(old,"blockId").isBlank()) throw error(403,"Only administrators can edit campus announcements"); a.duty("HOSTEL",str(old,"blockId")); }
            db.exec("UPDATE announcements SET title=?,body=?,level=?,audience=?,block_id=?,active=? WHERE id=?",title,body,level,audience,DirectoryService.nullable(block),b.getOrDefault("active",true),id);
        }
        db.audit(a,"SAVE_ANNOUNCEMENT","announcements",id,DirectoryService.nullable(block),title); return id;
    }
    @Transactional
    public void pollState(Actor a,String id,Map<String,Object> b) {
        var poll=db.one("SELECT * FROM polls WHERE id=? FOR UPDATE",id); directory.manageMess(a,str(poll,"messId"));
        db.exec("UPDATE polls SET enabled=? WHERE id=?",bool(b,"enabled"),id);
        db.audit(a,"SET_POLL_STATE","polls",id,null,"Enabled: "+bool(b,"enabled"));
    }
}
