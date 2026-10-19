package in.hostelcc;

import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import static in.hostelcc.Store.*;

@Service
public class StudentImport {
    final Store db; final DirectoryService directory;
    public StudentImport(Store db,DirectoryService directory) { this.db=db;this.directory=directory; }
    record Checked(List<Map<String,Object>> students,List<Map<String,Object>> errors) {}
    @Transactional
    public Map<String,Object> run(Actor actor,String csv,boolean commit) {
        actor.require("ADMIN");
        db.one("SELECT id FROM otp_guard WHERE id=1 FOR UPDATE");
        Checked checked=check(csv);
        if(commit&&!checked.errors().isEmpty()) throw error(400,"CSV validation failed. Preview the file and correct every row before importing.");
        if(commit) for(var student:checked.students()) directory.user(actor,null,student);
        return Map.of("valid",checked.errors().isEmpty(),"count",checked.students().size(),"errors",checked.errors(),"preview",checked.students().stream().limit(20).map(s->Map.of("name",s.get("name"),"email",s.get("email"),"rollNo",s.get("rollNo"))).toList(),"imported",commit?checked.students().size():0);
    }
    Checked check(String csv) {
        var table=parse(csv);if(table.size()<2) throw error(400,"CSV must contain a header and at least one student");
        var headers=table.getFirst().stream().map(String::strip).toList();
        var allowed=Set.of("name","email","rollNo","block","room","mess","phone","cloakroomAccess","messChangeAccess");
        if(new HashSet<>(headers).size()!=headers.size() || !headers.containsAll(List.of("name","email","rollNo","block")) || !allowed.containsAll(headers)) throw error(400,"Use the template headers: name,email,rollNo,block,room,mess,phone,cloakroomAccess,messChangeAccess");
        var results=new ArrayList<Map<String,Object>>();var errors=new ArrayList<Map<String,Object>>();
        var emails=new HashSet<String>();var rolls=new HashSet<String>();var rooms=new HashMap<String,Integer>();var messes=new HashMap<String,Integer>();
        for(int i=1;i<table.size();i++) {
            var cells=table.get(i);if(cells.stream().allMatch(String::isBlank)) continue;
            try {
                if(cells.size()!=headers.size()) throw error(400,"Column count does not match the header");
                var row=new HashMap<String,Object>();for(int c=0;c<headers.size();c++) row.put(headers.get(c),cells.get(c).strip());
                String name=required(row,"name",150),email=required(row,"email",254).toLowerCase(Locale.ROOT),roll=required(row,"rollNo",40);
                if(!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) throw error(400,"Invalid email address");
                if(!emails.add(email)||db.count("SELECT count(*) FROM users WHERE email=?",email)>0) throw error(400,"Email already exists or is repeated in this file");
                if(!rolls.add(roll)||db.count("SELECT count(*) FROM users WHERE roll_no=?",roll)>0) throw error(400,"Roll number already exists or is repeated in this file");
                String block=lookup("blocks","name",required(row,"block",100),null);
                String roomName=optional(row,"room",20),messName=optional(row,"mess",120);
                String room=roomName.isBlank()?"":lookup("rooms","number",roomName,block),mess=messName.isBlank()?"":lookup("messes","name",messName,null);
                if(!room.isBlank()) {
                    var r=db.one("SELECT capacity FROM rooms WHERE id=? FOR UPDATE",room);
                    int reserved=rooms.merge(room,1,Integer::sum);
                    if(db.count("SELECT count(*) FROM users WHERE room_id=? AND active=true",room)+reserved>((Number)r.get("capacity")).intValue()) throw error(400,"Room capacity would be exceeded");
                }
                if(!mess.isBlank()) {
                    var m=db.one("SELECT capacity FROM messes WHERE id=? FOR UPDATE",mess);
                    if(db.count("SELECT count(*) FROM mess_blocks WHERE mess_id=? AND block_id=?",mess,block)==0) throw error(400,"Mess does not serve the selected block");
                    int reserved=messes.merge(mess,1,Integer::sum);
                    if(db.count("SELECT count(*) FROM users WHERE mess_id=? AND active=true AND role='STUDENT'",mess)+reserved>((Number)m.get("capacity")).intValue()) throw error(400,"Mess capacity would be exceeded");
                }
                var student=new LinkedHashMap<String,Object>();student.put("name",name);student.put("email",email);student.put("rollNo",roll);student.put("role","STUDENT");student.put("blockId",block);student.put("roomId",room);student.put("messId",mess);student.put("phone",optional(row,"phone",30));student.put("active",true);
                for(String flag:List.of("cloakroomAccess","messChangeAccess")) {
                    String value=str(row,flag).toLowerCase(Locale.ROOT);if(!List.of("","true","false").contains(value)) throw error(400,flag+" must be true or false");student.put(flag,value.equals("true"));
                }
                results.add(student);
            } catch(org.springframework.web.server.ResponseStatusException e) { errors.add(Map.of("row",i+1,"message",Objects.requireNonNullElse(e.getReason(),"Invalid row"))); }
        }
        if(results.isEmpty()&&errors.isEmpty()) throw error(400,"No student rows found");
        return new Checked(results,errors);
    }
    String lookup(String table,String column,String value,String block) {
        var matches=block==null?db.list("SELECT id FROM "+table+" WHERE LOWER("+column+")=LOWER(?) AND active=true",value):db.list("SELECT id FROM "+table+" WHERE LOWER("+column+")=LOWER(?) AND block_id=? AND active=true",value,block);
        if(matches.size()!=1) throw error(400,"Unknown or ambiguous "+table+" value: "+value);
        return str(matches.getFirst(),"id");
    }
    static List<List<String>> parse(String source) {
        if(source==null||source.length()>500000) throw error(400,"CSV must be at most 500 KB and 1,000 students per batch");
        String s=source.startsWith("\uFEFF")?source.substring(1):source;
        var rows=new ArrayList<List<String>>();var row=new ArrayList<String>();var cell=new StringBuilder();boolean quoted=false,closed=false;
        for(int i=0;i<s.length();i++) {
            char c=s.charAt(i);
            if(quoted) {
                if(c=='"') { if(i+1<s.length()&&s.charAt(i+1)=='"') { cell.append('"');i++; } else { quoted=false;closed=true; } } else cell.append(c);
            } else if(c=='"') { if(cell.length()>0||closed) throw error(400,"Invalid CSV quoting");quoted=true; }
            else if(c==','||c=='\n'||c=='\r') {
                row.add(cell.toString());cell.setLength(0);closed=false;
                if(c!=',') { rows.add(row);row=new ArrayList<>();if(c=='\r'&&i+1<s.length()&&s.charAt(i+1)=='\n') i++; }
            } else { if(closed&&!Character.isWhitespace(c)) throw error(400,"Unexpected text after a quoted CSV field"); if(!closed) cell.append(c); }
            if(rows.size()>1001||row.size()>9) throw error(400,"Use at most 1,000 student rows and the template columns");
        }
        if(quoted) throw error(400,"Unclosed quoted CSV field");
        if(cell.length()>0||!row.isEmpty()||closed) { row.add(cell.toString());rows.add(row); }
        if(rows.size()>1001) throw error(400,"Import at most 1,000 students per batch");
        return rows;
    }
}

@RestController
@RequestMapping("/api/admin/students/import")
class StudentImportController {
    final StudentImport importer;
    StudentImportController(StudentImport importer) { this.importer=importer; }
    @PostMapping("/validate") Object validate(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object> body) { return importer.run(a,required(body,"csv",500000),false); }
    @PostMapping Object commit(@AuthenticationPrincipal Actor a,@RequestBody Map<String,Object> body) { return importer.run(a,required(body,"csv",500000),true); }
}
