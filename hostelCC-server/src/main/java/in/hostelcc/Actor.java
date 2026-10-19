package in.hostelcc;

import java.util.*;
import static in.hostelcc.Store.*;

public record Actor(String id,String role,String blockId,String messId,Set<String> blocks,String sessionId,List<Grant> scopes) {
    public record Grant(String book,String targetId) {}
    public boolean is(String... roles) { return List.of(roles).contains(role); }
    public boolean global() { return is("ADMIN","DIRECTOR"); }
    public boolean staff() { return is("ADMIN","WARDEN","SUPERVISOR","MESS_MANAGER","HOUSEKEEPING"); }
    public boolean has(String book,String target) { return is("ADMIN") || scopes.stream().anyMatch(g->g.book().equals(book)&&g.targetId().equals(target)); }
    public boolean hasBook(String book) { return is("ADMIN") || scopes.stream().anyMatch(g->g.book().equals(book)); }
    public void duty(String book,String target) { if(!has(book,target)) throw error(403,"You are not assigned to this "+book.toLowerCase(Locale.ROOT)+" book"); }
    public boolean sees(String book,Map<String,Object> row) { return global() || is("STUDENT") && id.equals(str(row,"studentId")) || has(book,str(row,"blockId")); }
    public void require(String... roles) { if(!is(roles)) throw error(403,"Your role cannot perform this action"); }
    public void block(String id) { if(!global() && !blocks.contains(id)) throw error(403,"This block is outside your assignment"); }
    public void person(Map<String,Object> row) {
        if(global()) return;
        if(is("STUDENT") && id.equals(str(row,"studentId"))) return;
        if(has("HOSTEL",str(row,"blockId"))) return;
        throw error(403,"This record is outside your access");
    }
    public boolean seesPerson(Map<String,Object> row) {
        return global() || is("STUDENT") && id.equals(str(row,"studentId")) || has("HOSTEL",str(row,"blockId"));
    }
}
