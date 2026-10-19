package in.hostelcc;

import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import static in.hostelcc.Store.*;

@Service
public class ResidenceService {
    final Store db; final DirectoryService directory;
    public ResidenceService(Store db,DirectoryService directory) { this.db=db;this.directory=directory; }
    @Transactional
    public String outing(Actor a,Map<String,Object> b) {
        a.require("STUDENT","ADMIN","WARDEN","SUPERVISOR"); String uid=a.is("STUDENT")?a.id():required(b,"studentId",64);
        var u=directory.student(uid); if(!a.is("STUDENT")) a.duty("OUTINGS",str(u,"blockId"));
        db.one("SELECT id FROM users WHERE id=? FOR UPDATE",uid);
        String kind=choice(b,"kind","OUTING","LEAVE","NIGHT_MESS"),destination=required(b,"destination",200),reason=required(b,"reason",2000),departure=instant(b,"departureAt"),expected=instant(b,"expectedReturnAt");
        if(!Instant.parse(expected).isAfter(Instant.parse(departure)) || !Instant.parse(expected).isAfter(Instant.now())) throw error(400,"Return time must follow departure and be in the future");
        if(db.count("SELECT count(*) FROM outings WHERE student_id=? AND status IN ('PENDING','APPROVED','OUT')",uid)>0) throw error(409,"Finish or cancel the student's active outing first");
        String id=id(); db.exec("INSERT INTO outings(id,student_id,block_id,kind,destination,reason,departure_at,expected_return_at,status,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",id,uid,str(u,"blockId"),kind,destination,reason,departure,expected,"PENDING",now());
        db.audit(a,"REQUEST_OUTING","outings",id,str(u,"blockId"),kind); return id;
    }
    @Transactional
    public void outingAction(Actor a,String id,Map<String,Object> b) {
        var row=db.one("SELECT * FROM outings WHERE id=? FOR UPDATE",id);
        if(!a.sees("OUTINGS",row)) throw error(403,"This outing is outside your assignment");
        String action=choice(b,"action","approve","reject","exit","enter","cancel"),status=str(row,"status"),note=optional(b,"note",2000);
        if(!action.equals("cancel") || !a.is("STUDENT")) a.duty("OUTINGS",str(row,"blockId"));
        switch(action) {
            case "approve","reject" -> {
                if(!status.equals("PENDING")) throw error(409,"Only pending requests can be decided");
                if(action.equals("approve") && !Instant.parse(str(row,"expectedReturnAt")).isAfter(Instant.now())) throw error(409,"This request has expired");
                if(action.equals("reject") && note.isBlank()) throw error(400,"Give a reason for rejection");
                db.exec("UPDATE outings SET status=?,decision_note=?,decided_by=? WHERE id=?",action.equals("approve")?"APPROVED":"REJECTED",note,a.id(),id);
            }
            case "exit" -> {
                if(!status.equals("APPROVED")) throw error(409,"An approved outing is required before exit");
                Instant departure=Instant.parse(str(row,"departureAt"));
                if(Instant.now().isBefore(departure.minusSeconds(1800)) || !Instant.parse(str(row,"expectedReturnAt")).isAfter(Instant.now())) throw error(409,"Exit is allowed from 30 minutes before departure until the expected return");
                db.exec("UPDATE outings SET status='OUT',exited_at=? WHERE id=?",now(),id);
            }
            case "enter" -> { if(!status.equals("OUT")) throw error(409,"Record an exit before entry"); db.exec("UPDATE outings SET status='RETURNED',entered_at=? WHERE id=?",now(),id); }
            case "cancel" -> { if(!List.of("PENDING","APPROVED").contains(status)) throw error(409,"This outing cannot be cancelled"); db.exec("UPDATE outings SET status='CANCELLED',decision_note=? WHERE id=?",note,id); }
        }
        db.audit(a,"OUTING_"+action.toUpperCase(Locale.ROOT),"outings",id,str(row,"blockId"),note);
    }
    @Transactional
    public String discipline(Actor a,Map<String,Object> b) {
        var u=directory.student(required(b,"studentId",64)); a.duty("DISCIPLINE",str(u,"blockId")); String uid=str(u,"id");
        db.one("SELECT id FROM users WHERE id=? FOR UPDATE",uid);
        String violation=required(b,"violation",200),action=required(b,"actionTaken",500),notes=optional(b,"notes",4000);
        long occurrence=db.count("SELECT count(*) FROM discipline WHERE student_id=? AND violation=?",uid,violation)+1;
        String id=id(); db.exec("INSERT INTO discipline(id,student_id,block_id,violation,action_taken,notes,occurrence_number,card_held,created_by,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",id,uid,str(u,"blockId"),violation,action,notes,occurrence,bool(b,"cardHeld"),a.id(),now());
        db.audit(a,"ADD_DISCIPLINE","discipline",id,str(u,"blockId"),violation); return id;
    }
    @Transactional
    public void returnCard(Actor a,String id,Map<String,Object> b) {
        var row=db.one("SELECT * FROM discipline WHERE id=? FOR UPDATE",id); a.duty("DISCIPLINE",str(row,"blockId"));
        if(!bool(row,"cardHeld") || row.get("cardReturnedAt")!=null) throw error(409,"No held ID card remains on this record");
        String note=required(b,"note",2000); db.exec("UPDATE discipline SET card_returned_at=?,return_notes=? WHERE id=?",now(),note,id);
        db.audit(a,"RETURN_ID_CARD","discipline",id,str(row,"blockId"),note);
    }
    @Transactional
    public String cloakroom(Actor a,Map<String,Object> b) {
        var u=directory.student(required(b,"studentId",64));
        String uid=str(u,"id"),block=str(u,"blockId"),storage=required(b,"storageId",64),item=choice(b,"item","CHAIR","BUCKET","CARTON","SUITCASE","MATTRESS","OTHER"),condition=choice(b,"itemCondition","GOOD","DAMAGED");
        a.duty("CLOAKROOM",storage);
        db.one("SELECT id FROM users WHERE id=? FOR UPDATE",uid);
        if(!bool(u,"cloakroomAccess")) throw error(403,"An administrator must enable cloakroom access for this student");
        storageCapacity(storage,block);
        var room=db.one("SELECT * FROM storage_rooms WHERE id=? FOR UPDATE",storage);
        if(!str(room,"itemType").equals(item)) throw error(400,"This room stores a different item type");
        int token=((Number)room.get("nextToken")).intValue();
        if(token>((Number)room.get("tokenEnd")).intValue()) throw error(409,"This cloakroom's token range is exhausted");
        if(db.count("SELECT count(*) FROM cloakroom WHERE student_id=? AND item=? AND status='STORED'",uid,item)>0) throw error(409,"This item already has an active receipt");
        if(!item.equals("CHAIR") && db.count("SELECT count(*) FROM cloakroom WHERE student_id=? AND item='CHAIR' AND status='STORED'",uid)==0) throw error(409,"Submit the chair before other items");
        String id=id(),receipt="HC-"+UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
        db.exec("INSERT INTO cloakroom(id,receipt,student_id,block_id,storage_id,item,item_condition,notes,status,submitted_by,submitted_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",id,receipt,uid,block,storage,item,condition,optional(b,"notes",4000),"STORED",a.id(),now());
        db.exec("UPDATE cloakroom SET token_number=?,token_room_id=? WHERE id=?",token,storage,id);
        db.exec("UPDATE storage_rooms SET next_token=next_token+1 WHERE id=?",storage);
        db.audit(a,"STORE_ITEM","cloakroom",id,block,"Receipt "+receipt+"; storage "+storage); return id;
    }
    void storageCapacity(String id,String block) {
        var room=db.one("SELECT * FROM storage_rooms WHERE id=? AND block_id=? AND active=true FOR UPDATE",id,block);
        if(db.count("SELECT count(*) FROM cloakroom WHERE storage_id=? AND status='STORED'",id)>=((Number)room.get("capacity")).intValue()) throw error(409,"Storage room is full");
    }
    @Transactional
    public void cloakroomAction(Actor a,String id,Map<String,Object> b) {
        var row=db.one("SELECT * FROM cloakroom WHERE id=? FOR UPDATE",id); a.duty("CLOAKROOM",str(row,"storageId"));
        if(!str(row,"status").equals("STORED")) throw error(409,"This item was already returned");
        String action=choice(b,"action","return","move"),note=required(b,"note",2000);
        if(action.equals("return")) {
            if(!required(b,"receipt",64).equals(str(row,"receipt"))) throw error(400,"Receipt does not match this item");
            db.exec("UPDATE cloakroom SET status='RETURNED',returned_at=?,returned_by=? WHERE id=?",now(),a.id(),id);
        } else {
            String target=required(b,"storageId",64); if(target.equals(str(row,"storageId"))) throw error(400,"Select a different storage room");
            a.duty("CLOAKROOM",target);
            storageCapacity(target,str(row,"blockId"));
            var targetRoom=db.one("SELECT item_type FROM storage_rooms WHERE id=?",target);
            if(!str(targetRoom,"itemType").equals(str(row,"item"))) throw error(400,"Target room must store the same item type");
            db.exec("UPDATE cloakroom SET storage_id=? WHERE id=?",target,id);
            note="From "+str(row,"storageId")+" to "+target+". "+note;
        }
        db.audit(a,action.equals("return")?"RETURN_ITEM":"MOVE_ITEM","cloakroom",id,str(row,"blockId"),note);
    }
    @Transactional
    public String maintenance(Actor a,Map<String,Object> b) {
        a.require("STUDENT","ADMIN","WARDEN","SUPERVISOR");
        String block=a.is("STUDENT")?a.blockId():required(b,"blockId",64); if(!a.is("STUDENT")) a.duty("MAINTENANCE",block); db.one("SELECT id FROM blocks WHERE id=? AND active=true",block);
        String category=choice(b,"category","CLEANING","PLUMBING","ELECTRICAL","CARPENTRY","WATER","AC","OTHER"),description=required(b,"description",4000),room=optional(b,"roomLabel",40);
        if(a.is("STUDENT")) { var u=db.one("SELECT r.number FROM users u LEFT JOIN rooms r ON r.id=u.room_id WHERE u.id=?",a.id()); room=str(u,"number"); }
        String id=id(); db.exec("INSERT INTO maintenance(id,student_id,block_id,room_label,category,description,status,created_at,updated_at) VALUES(?,?,?,?,?,?,'OPEN',?,?)",id,a.is("STUDENT")?a.id():null,block,room,category,description,now(),now());
        db.audit(a,"OPEN_MAINTENANCE","maintenance",id,block,category); return id;
    }
    @Transactional
    public void maintenanceAction(Actor a,String id,Map<String,Object> b) {
        var row=db.one("SELECT * FROM maintenance WHERE id=? FOR UPDATE",id); a.duty("MAINTENANCE",str(row,"blockId"));
        if(a.is("HOUSEKEEPING") && !a.id().equals(str(row,"assigneeId"))) throw error(403,"This task is not assigned to you");
        String action=choice(b,"action","assign","start","resolve","reopen");
        if(action.equals("assign")) {
            a.require("ADMIN","WARDEN","SUPERVISOR"); String uid=required(b,"assigneeId",64);
            db.one("SELECT u.id FROM users u JOIN duty_scopes s ON s.user_id=u.id WHERE u.id=? AND u.role='HOUSEKEEPING' AND u.active=true AND s.active=true AND s.book='MAINTENANCE' AND s.target_id=?",uid,str(row,"blockId"));
            if(str(row,"status").equals("RESOLVED")) throw error(409,"Reopen the task before assigning it");
            db.exec("UPDATE maintenance SET assignee_id=?,updated_at=? WHERE id=?",uid,now(),id);
        } else {
            String status=str(row,"status"),next;
            if(action.equals("start")) { if(!status.equals("OPEN") || str(row,"assigneeId").isBlank()) throw error(409,"Assign an open task first"); next="IN_PROGRESS"; }
            else if(action.equals("resolve")) { if(!status.equals("IN_PROGRESS")) throw error(409,"Start the task before resolving it"); next="RESOLVED"; }
            else { a.require("ADMIN","WARDEN","SUPERVISOR"); if(!status.equals("RESOLVED")) throw error(409,"Only resolved tasks can be reopened"); next="OPEN"; }
            String resolution=action.equals("resolve")?required(b,"resolution",2000):str(row,"resolution");
            db.exec("UPDATE maintenance SET status=?,resolution=?,updated_at=? WHERE id=?",next,resolution,now(),id);
        }
        db.audit(a,"MAINTENANCE_"+action.toUpperCase(Locale.ROOT),"maintenance",id,str(row,"blockId"),optional(b,"resolution",2000));
    }
}
