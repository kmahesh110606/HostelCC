package in.hostelcc;

import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import tools.jackson.databind.ObjectMapper;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static in.hostelcc.Store.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"spring.datasource.url=${TEST_DB_URL:jdbc:h2:mem:workflow;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1}","spring.datasource.username=${TEST_DB_USER:sa}","spring.datasource.password=${TEST_DB_PASSWORD:}","app.jwt-secret=test-only-secret-with-at-least-thirty-two-bytes","app.cookie-secure=false","app.admin-email=","app.bootstrap-required=false","spring.profiles.active=test","logging.level.root=WARN","logging.level.org.springframework=WARN","debug=false"})
class WorkflowTest {
    @LocalServerPort int port;
    @Autowired Store db;
    @Autowired ObjectMapper json;
    @MockitoBean CodeMailer mail;
    final Map<String,String> codes=new ConcurrentHashMap<>();
    record Reply(int status,Map<String,Object> body,HttpHeaders headers) {}
    class Client {
        final CookieManager jar=new CookieManager(null,CookiePolicy.ACCEPT_ALL);
        final HttpClient http=HttpClient.newBuilder().cookieHandler(jar).build(); String csrf;
        Reply call(String method,String path,Map<String,Object> body) throws Exception { return call(method,path,body,true); }
        Reply call(String method,String path,Map<String,Object> body,boolean retry) throws Exception {
            if(!method.equals("GET")&&csrf==null) csrf=str(call("GET","/auth/csrf",null).body(),"token");
            var request=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api"+path)).header("Content-Type","application/json");
            if(!method.equals("GET")) request.header("X-XSRF-TOKEN",csrf);
            request.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
            var response=http.send(request.build(),HttpResponse.BodyHandlers.ofString());
            if(response.statusCode()==403 && response.body().contains("CSRF") && retry) { csrf=null; return call(method,path,body,false); }
            return new Reply(response.statusCode(),json.readValue(response.body(),Map.class),response.headers());
        }
        Reply login(String uid,boolean remember) throws Exception {
            String email=uid+"@example.test";
            assertEquals(200,call("POST","/auth/request-code",Map.of("email",email)).status());
            return call("POST","/auth/verify-code",Map.of("email",email,"code",codes.get(email),"remember",remember));
        }
    }
    @BeforeEach void setup() {
        for(String table:List.of("cloakroom_requests","audit","votes","poll_options","polls","feedback","menus","mess_changes","maintenance","cloakroom","discipline","outings","announcements","sessions","otp_challenges","otp_requests","duty_scopes","users","storage_rooms","rooms","mess_blocks","messes","blocks")) db.exec("DELETE FROM "+table);
        codes.clear(); doAnswer(inv->{ codes.put(inv.getArgument(0),inv.getArgument(1)); return null; }).when(mail).send(anyString(),anyString());
        for(String b:List.of("A","B")) db.exec("INSERT INTO blocks(id,name) VALUES(?,?)",b,"Block "+b);
        db.exec("INSERT INTO messes(id,name,capacity) VALUES('M','Main Mess',100)"); db.exec("INSERT INTO mess_blocks VALUES('M','A')"); db.exec("INSERT INTO mess_blocks VALUES('M','B')");
        user("admin","ADMIN",null); user("director","DIRECTOR",null); user("warden","WARDEN",null); user("supervisor","SUPERVISOR",null); user("messwarden","WARDEN",null); user("house","HOUSEKEEPING",null); user("student","STUDENT","A"); user("other","STUDENT","B"); user("second","STUDENT","A");
        scope("warden","HOSTEL","A");scope("warden","DISCIPLINE","A");scope("supervisor","OUTINGS","A");scope("messwarden","MESS","M");
        storage("CHAIR_A","A","CHAIR",100,101); storage("BUCKET_A","A","BUCKET",200,201); storage("CHAIR_B","B","CHAIR",100,101);
        scope("house","CLOAKROOM","CHAIR_A");scope("house","CLOAKROOM","BUCKET_A");scope("house","MAINTENANCE","A");scope("warden","MAINTENANCE","A");
    }
    void user(String uid,String role,String block) { db.exec("INSERT INTO users(id,email,name,role,block_id,mess_id,roll_no,cloakroom_access,created_at) VALUES(?,?,?,?,?,'M',?,true,?)",uid,uid+"@example.test",uid,role,block,role.equals("STUDENT")?uid:null,now()); }
    void scope(String uid,String book,String target) { db.exec("INSERT INTO duty_scopes(id,user_id,book,target_id) VALUES(?,?,?,?)",id(),uid,book,target); }
    void storage(String uid,String block,String item,int start,int end) { db.exec("INSERT INTO storage_rooms(id,block_id,name,capacity,item_type,token_start,token_end,next_token) VALUES(?,?,?,10,?,?,?,?)",uid,block,uid,item,start,end,start); }
    Client signed(String uid) throws Exception { var c=new Client(); assertEquals(200,c.login(uid,true).status()); return c; }
    List<Map<String,Object>> rows(Reply r,String key) { return (List<Map<String,Object>>)r.body().get(key); }
    Map<String,Object> outing() { return Map.of("kind","OUTING","destination","Library","reason","Study","departureAt",Instant.now().toString(),"expectedReturnAt",Instant.now().plusSeconds(3600).toString()); }
    @Test void editingDutyReplacesAccessAndInactiveAssignmentsCanBeRevoked() throws Exception {
        var admin=signed("admin"); var supervisor=signed("supervisor");
        String grant=str(db.one("SELECT id FROM duty_scopes WHERE user_id='supervisor' AND book='OUTINGS'"),"id");
        assertTrue(rows(supervisor.call("GET","/workspace",null),"users").stream().anyMatch(u->str(u,"id").equals("student")));
        var changed=admin.call("PUT","/scopes/"+grant,Map.of("userId","supervisor","book","OUTINGS","targetId","B","active",true));
        assertEquals(200,changed.status());
        var users=rows(supervisor.call("GET","/workspace",null),"users");
        assertFalse(users.stream().anyMatch(u->str(u,"id").equals("student")));
        assertTrue(users.stream().anyMatch(u->str(u,"id").equals("other")));
        assertEquals(1,db.count("SELECT count(*) FROM duty_scopes WHERE user_id='supervisor' AND active=true"));
        db.exec("UPDATE users SET active=false WHERE id='supervisor'");
        db.exec("UPDATE blocks SET active=false WHERE id='B'");
        assertEquals(200,admin.call("PUT","/scopes/"+grant,Map.of("userId","supervisor","book","OUTINGS","targetId","B","active",false)).status());
        assertEquals(0,db.count("SELECT count(*) FROM duty_scopes WHERE user_id='supervisor' AND active=true"));
    }
    @Test void mailFailureStillEnforcesCooldown() throws Exception {
        doThrow(new org.springframework.mail.MailSendException("Test provider offline")).when(mail).send(anyString(),anyString());
        var client=new Client();
        assertEquals(503,client.call("POST","/auth/request-code",Map.of("email","student@example.test")).status());
        assertEquals(429,client.call("POST","/auth/request-code",Map.of("email","student@example.test")).status());
    }
    @Test void paginatedSearchAndTotalsStayScopedWithTwoThousandStudents() throws Exception {
        for(int i=0;i<2100;i++) user("bulk"+String.format("%04d",i),"STUDENT",i%2==0?"A":"B");
        var admin=signed("admin");var warden=signed("warden");
        var all=admin.call("GET","/records/users?page=1&size=25&q=bulk",null);
        assertEquals(200,all.status());assertEquals(2100,((Number)all.body().get("total")).intValue());assertEquals(25,rows(all,"items").size());
        var scoped=warden.call("GET","/records/users?size=25&q=bulk",null);
        assertEquals(1050,((Number)scoped.body().get("total")).intValue());assertTrue(rows(scoped,"items").stream().allMatch(u->str(u,"blockId").equals("A")));
        assertEquals(0,((Number)warden.call("GET","/records/users?q=bulk0001",null).body().get("total")).intValue());
        var workspace=warden.call("GET","/workspace",null);
        assertTrue(rows(workspace,"users").size()<=25);
        assertEquals(1052,((Number)((Map<?,?>)workspace.body().get("stats")).get("students")).intValue());
        assertEquals(400,admin.call("GET","/records/users?size=10000",null).status());
    }
    @Test void csvPreviewIsNonMutatingAndImportIsAtomic() throws Exception {
        var admin=signed("admin");var student=signed("student");
        String csv="name,email,rollNo,block,room,mess,phone,cloakroomAccess,messChangeAccess\r\n\"Rao, Ananya\",csv@example.test,CSV001,Block A,,Main Mess,,true,false\r\n";
        long before=db.count("SELECT count(*) FROM users");
        assertEquals(403,student.call("POST","/admin/students/import/validate",Map.of("csv",csv)).status());
        var preview=admin.call("POST","/admin/students/import/validate",Map.of("csv",csv));
        assertEquals(200,preview.status());assertEquals(true,preview.body().get("valid"));assertEquals(before,db.count("SELECT count(*) FROM users"));
        String invalid=csv+"Wrong Block,wrong@example.test,CSV002,Missing Block,,Main Mess,,false,false\n";
        assertEquals(false,admin.call("POST","/admin/students/import/validate",Map.of("csv",invalid)).body().get("valid"));
        assertEquals(400,admin.call("POST","/admin/students/import",Map.of("csv",invalid)).status());assertEquals(before,db.count("SELECT count(*) FROM users"));
        assertEquals(1,((Number)admin.call("POST","/admin/students/import",Map.of("csv",csv)).body().get("imported")).intValue());
        assertEquals("Rao, Ananya",str(db.one("SELECT name FROM users WHERE email='csv@example.test'"),"name"));
        assertEquals(400,admin.call("POST","/admin/students/import",Map.of("csv",csv)).status());
        assertEquals(before+1,db.count("SELECT count(*) FROM users"));
    }
    @Test void cookieOtpCsrfAndRevocation() throws Exception {
        var c=new Client(); var login=c.login("student",true); assertEquals(200,login.status());
        String cookie=login.headers().allValues("set-cookie").stream().filter(s->s.startsWith("HOSTELCC_SESSION=")).findFirst().orElseThrow();
        assertTrue(cookie.contains("HttpOnly")); assertTrue(cookie.contains("Max-Age=2592000")); assertTrue(cookie.contains("SameSite=Lax")); assertFalse(login.body().containsKey("token"));
        var replay=new Client();
        for(var stored:c.jar.getCookieStore().getCookies()) replay.jar.getCookieStore().add(URI.create("http://localhost:"+port), (HttpCookie)stored.clone());
        assertEquals(400,c.call("POST","/auth/verify-code",Map.of("email","student@example.test","code",codes.get("student@example.test"))).status());
        var raw=c.http.send(HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/outings")).header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(outing()))).build(),HttpResponse.BodyHandlers.ofString());
        assertEquals(403,raw.statusCode());
        assertEquals(200,c.call("POST","/auth/logout",Map.of()).status()); assertEquals(401,c.call("GET","/auth/me",null).status());
        assertEquals(401,replay.call("GET","/auth/me",null).status());
    }
    @Test void codesExpireAndWrongAttemptsArePersisted() throws Exception {
        var c=new Client(); c.call("POST","/auth/request-code",Map.of("email","student@example.test"));
        String wrong=codes.get("student@example.test").equals("000000")?"111111":"000000";
        for(int i=0;i<5;i++) assertEquals(400,c.call("POST","/auth/verify-code",Map.of("email","student@example.test","code",wrong)).status());
        assertEquals(400,c.call("POST","/auth/verify-code",Map.of("email","student@example.test","code",codes.get("student@example.test"))).status());
        assertEquals(5,db.count("SELECT attempts FROM otp_challenges WHERE user_id='student'"));
        c.call("POST","/auth/request-code",Map.of("email","other@example.test")); db.exec("UPDATE otp_challenges SET expires_at=? WHERE user_id='other'",Instant.now().minusSeconds(1).toString());
        assertEquals(400,c.call("POST","/auth/verify-code",Map.of("email","other@example.test","code",codes.get("other@example.test"))).status());
    }
    @Test void unknownEmailAndResendAreSafe() throws Exception {
        var c=new Client(); assertEquals(200,c.call("POST","/auth/request-code",Map.of("email","unknown@example.test")).status()); assertFalse(codes.containsKey("unknown@example.test"));
        assertEquals(429,c.call("POST","/auth/request-code",Map.of("email","unknown@example.test")).status());
        assertEquals(200,c.login("student",false).status());
        assertTrue(c.jar.getCookieStore().getCookies().stream().filter(k->k.getName().equals("HOSTELCC_SESSION")).allMatch(k->k.getMaxAge()==-1));
    }
    @Test void dutyBooksLimitReadsAndMutations() throws Exception {
        var student=signed("student"); var other=signed("other");
        String own=str(student.call("POST","/outings",outing()).body(),"id"); String foreign=str(other.call("POST","/outings",outing()).body(),"id");
        var warden=signed("warden"); var supervisor=signed("supervisor"); var director=signed("director");
        assertEquals(0,rows(warden.call("GET","/workspace",null),"outings").size());
        assertEquals(1,rows(supervisor.call("GET","/workspace",null),"outings").size());
        assertEquals(2,rows(director.call("GET","/workspace",null),"outings").size());
        assertEquals(403,warden.call("POST","/outings/"+own+"/action",Map.of("action","approve")).status());
        assertEquals(403,supervisor.call("POST","/outings/"+foreign+"/action",Map.of("action","approve")).status());
        assertEquals(403,director.call("POST","/outings/"+own+"/action",Map.of("action","approve")).status());
        assertEquals(200,supervisor.call("POST","/outings/"+own+"/action",Map.of("action","approve")).status());
        assertEquals(403,student.call("GET","/admin/export",null).status());
        db.exec("UPDATE duty_scopes SET active=false WHERE user_id='supervisor'");
        assertEquals(403,supervisor.call("POST","/outings/"+own+"/action",Map.of("action","exit")).status());
    }
    @Test void outingsHaveOrderedImmutableEvents() throws Exception {
        var s=signed("student"); var staff=signed("supervisor"); String id=str(s.call("POST","/outings",outing()).body(),"id");
        assertEquals(409,s.call("POST","/outings",outing()).status());
        assertEquals(409,staff.call("POST","/outings/"+id+"/action",Map.of("action","exit")).status());
        for(String action:List.of("approve","exit","enter")) assertEquals(200,staff.call("POST","/outings/"+id+"/action",Map.of("action",action)).status());
        assertEquals(409,staff.call("POST","/outings/"+id+"/action",Map.of("action","enter")).status());
        assertNotNull(db.one("SELECT * FROM outings WHERE id=?",id).get("exitedAt")); assertEquals(4,db.count("SELECT count(*) FROM audit WHERE resource_id=?",id));
    }
    Map<String,Object> scanBody(String qr,String room) { return Map.of("storageId",room,"qrToken",qr,"mode","submit","itemCondition","GOOD"); }
    @Test void cloakroomScanIsScopedOrderedAndIdempotent() throws Exception {
        var s=signed("student"); var staff=signed("house"); var warden=signed("warden");
        String chair=str(s.call("POST","/cloakroom/request",Map.of("storageId","CHAIR_A")).body(),"qrToken");
        String bucket=str(s.call("POST","/cloakroom/request",Map.of("storageId","BUCKET_A")).body(),"qrToken");
        assertEquals(409,staff.call("POST","/cloakroom/scan",scanBody(bucket,"BUCKET_A")).status());
        assertEquals(403,warden.call("POST","/cloakroom/scan",scanBody(chair,"CHAIR_A")).status());
        assertEquals(403,staff.call("POST","/cloakroom/scan",scanBody(chair,"CHAIR_B")).status());
        var first=staff.call("POST","/cloakroom/scan",scanBody(chair,"CHAIR_A")); assertEquals(200,first.status()); assertEquals(100,((Number)first.body().get("tokenNumber")).intValue());
        var repeat=staff.call("POST","/cloakroom/scan",scanBody(chair,"CHAIR_A")); assertEquals(first.body().get("id"),repeat.body().get("id")); assertEquals(101,db.count("SELECT next_token FROM storage_rooms WHERE id='CHAIR_A'"));
        assertEquals(200,staff.call("POST","/cloakroom/scan",scanBody(bucket,"BUCKET_A")).status());
        assertEquals(200,staff.call("POST","/cloakroom/scan",Map.of("storageId","CHAIR_A","qrToken",chair,"mode","return","notes","Collected by student")).status());
        assertEquals("RETURNED",db.one("SELECT * FROM cloakroom WHERE id=?",first.body().get("id")).get("status"));
        assertEquals(0,rows(signed("other").call("GET","/workspace",null),"cloakroom").size());
    }
    @Test void simultaneousScansIssueDistinctTokensAndNeverOverflow() throws Exception {
        var s=signed("student"); var s2=signed("second"); var staff=signed("house");
        String q1=str(s.call("POST","/cloakroom/request",Map.of("storageId","CHAIR_A")).body(),"qrToken"),q2=str(s2.call("POST","/cloakroom/request",Map.of("storageId","CHAIR_A")).body(),"qrToken");
        try(var pool=Executors.newFixedThreadPool(2)) {
            var f1=pool.submit(()->staff.call("POST","/cloakroom/scan",scanBody(q1,"CHAIR_A")));
            var f2=pool.submit(()->staff.call("POST","/cloakroom/scan",scanBody(q2,"CHAIR_A")));
            var r1=f1.get(); var r2=f2.get(); assertEquals(200,r1.status()); assertEquals(200,r2.status()); assertNotEquals(r1.body().get("tokenNumber"),r2.body().get("tokenNumber"));
        }
        staff.call("POST","/cloakroom/scan",Map.of("storageId","CHAIR_A","qrToken",q1,"mode","return","notes","Collected"));
        String q3=str(s.call("POST","/cloakroom/request",Map.of("storageId","CHAIR_A")).body(),"qrToken");
        assertEquals(409,staff.call("POST","/cloakroom/scan",scanBody(q3,"CHAIR_A")).status());
        assertEquals(2,db.count("SELECT count(*) FROM cloakroom"));
    }
    @Test void messWardenCanEditMenuAndDisablePollWithoutStudentRecords() throws Exception {
        var w=signed("messwarden"); var student=signed("student");
        assertEquals(0,rows(w.call("GET","/workspace",null),"users").size());
        assertEquals(200,w.call("POST","/menus",Map.of("messId","M","day","MON","breakfast","Idli","lunch","Rice","snacks","Tea","dinner","Roti")).status());
        String poll=str(w.call("POST","/polls",Map.of("messId","M","title","Next menu","closesAt",Instant.now().plusSeconds(3600).toString(),"options",List.of("Dosa","Idli"))).body(),"id");
        String option=str(db.one("SELECT id FROM poll_options WHERE poll_id=?",poll),"id");
        assertEquals(200,w.call("POST","/polls/"+poll+"/state",Map.of("enabled",false)).status());
        assertEquals(409,student.call("POST","/polls/"+poll+"/action",Map.of("optionId",option)).status());
        w.call("POST","/polls/"+poll+"/state",Map.of("enabled",true));
        assertEquals(200,student.call("POST","/polls/"+poll+"/action",Map.of("optionId",option)).status());
        assertEquals(409,student.call("POST","/polls/"+poll+"/action",Map.of("optionId",option)).status());
    }
    @Test void housekeepingSeesOnlyAssignedTasksAndCompletesWorkflow() throws Exception {
        var student=signed("student");var w=signed("warden");var h=signed("house");
        String task=str(student.call("POST","/maintenance",Map.of("category","CLEANING","description","Clean corridor")).body(),"id");
        assertEquals(0,rows(h.call("GET","/workspace",null),"maintenance").size());
        assertEquals(200,w.call("POST","/maintenance/"+task+"/action",Map.of("action","assign","assigneeId","house")).status());
        assertEquals(1,rows(h.call("GET","/workspace",null),"maintenance").size());
        assertEquals(200,h.call("POST","/maintenance/"+task+"/action",Map.of("action","start")).status());
        assertEquals(200,h.call("POST","/maintenance/"+task+"/action",Map.of("action","resolve","resolution","Corridor cleaned")).status());
    }
    @Test void administratorControlsCapacityAndRoleAssignments() throws Exception {
        var admin=signed("admin");var warden=signed("warden");
        assertEquals(403,warden.call("POST","/scopes",Map.of("userId","warden","book","OUTINGS","targetId","B","active",true)).status());
        assertEquals(400,admin.call("POST","/scopes",Map.of("userId","house","book","DISCIPLINE","targetId","A","active",true)).status());
        String room=str(admin.call("POST","/rooms",Map.of("blockId","A","number","101","capacity",1,"roomType","AC")).body(),"id");
        Map<String,Object> first=new HashMap<>(Map.of("name","First","email","first@example.test","role","STUDENT","blockId","A","roomId",room,"messId","M","rollNo","FIRST","active",true));
        assertEquals(200,admin.call("POST","/users",first).status()); first.put("email","third@example.test");first.put("rollNo","THIRD");
        assertEquals(409,admin.call("POST","/users",first).status());
        assertEquals(409,admin.call("PUT","/blocks/A",Map.of("name","Block A","active",false)).status());
        assertEquals(200,admin.call("GET","/admin/export",null).status());
        assertEquals(403,signed("director").call("POST","/blocks",Map.of("name","Blocked mutation")).status());
    }
    @Test void disciplineIsVisibleOnlyToItsStudentAndAssignedBook() throws Exception {
        var warden=signed("warden");var student=signed("student");
        String record=str(warden.call("POST","/discipline",Map.of("studentId","student","violation","Quiet hours","actionTaken","Reminder","cardHeld",true)).body(),"id");
        assertEquals(1,rows(student.call("GET","/workspace",null),"discipline").size());
        assertEquals(0,rows(signed("other").call("GET","/workspace",null),"discipline").size());
        assertEquals(403,student.call("POST","/discipline/"+record+"/action",Map.of("note","Return")).status());
        assertEquals(200,warden.call("POST","/discipline/"+record+"/action",Map.of("note","Collected")).status());
        assertEquals(409,warden.call("POST","/discipline/"+record+"/action",Map.of("note","Again")).status());
    }
    @Test void simultaneousOtpVerificationSucceedsOnlyOnce() throws Exception {
        var c=new Client(); c.call("POST","/auth/request-code",Map.of("email","student@example.test"));
        var c2=new Client(); c2.call("GET","/auth/csrf",null);
        var body=Map.<String,Object>of("email","student@example.test","code",codes.get("student@example.test"),"remember",true);
        try(var pool=Executors.newFixedThreadPool(2)) {
            var f1=pool.submit(()->c.call("POST","/auth/verify-code",body));var f2=pool.submit(()->c2.call("POST","/auth/verify-code",body));
            var statuses=new ArrayList<>(List.of(f1.get().status(),f2.get().status()));Collections.sort(statuses);assertEquals(List.of(200,400),statuses);
        }
        assertEquals(1,db.count("SELECT count(*) FROM sessions WHERE user_id='student'"));
    }
}
