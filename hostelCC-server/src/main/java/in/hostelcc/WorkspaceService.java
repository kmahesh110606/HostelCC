package in.hostelcc;

import java.util.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;
import static in.hostelcc.Store.*;

@Service
public class WorkspaceService {
    final Store db; final RecordService records; final ObjectMapper json;
    static final List<String> COLLECTIONS=List.of("blocks","rooms","users","announcements","messes","menus","feedback","polls","outings","discipline","cloakroom","storageRooms","cloakroomRequests","maintenance","messChanges","audit","scopes");
    public WorkspaceService(Store db,RecordService records,ObjectMapper json) { this.db=db;this.records=records;this.json=json; }
    @Transactional(readOnly=true)
    public Map<String,Object> load(Actor a) {
        var result=new LinkedHashMap<String,Object>();var pagination=new LinkedHashMap<String,Object>();
        for(String collection:COLLECTIONS) {
            var page=records.page(a,collection,0,25,"");result.put(collection,page.get("items"));
            pagination.put(collection,Map.of("page",0,"size",25,"total",page.get("total")));
        }
        result.put("pagination",pagination);
        var stats=new LinkedHashMap<String,Object>();
        stats.put("students",records.count(a,"users","t.role='STUDENT' AND t.active=true"));
        stats.put("blocks",records.count(a,"blocks","t.active=true"));
        stats.put("studentsOut",records.count(a,"outings","t.status='OUT'"));
        stats.put("pendingOutings",records.count(a,"outings","t.status='PENDING'"));
        stats.put("overdue",records.count(a,"outings","t.status='OUT' AND t.expected_return_at<:now"));
        stats.put("storedItems",records.count(a,"cloakroom","t.status='STORED'"));
        stats.put("openTasks",records.count(a,"maintenance","t.status<>'RESOLVED'"));
        stats.put("messRating",records.rating(a));result.put("stats",stats);return result;
    }
    @Transactional(readOnly=true)
    public void export(Actor a,OutputStream output) throws IOException {
        a.require("ADMIN");output.write('{');boolean firstTable=true;
        for(String table:List.of("blocks","rooms","messes","mess_blocks","users","duty_scopes","announcements","menus","feedback","polls","poll_options","votes","outings","discipline","storage_rooms","cloakroom","maintenance","mess_changes","audit")) {
            if(!firstTable) output.write(',');firstTable=false;
            output.write(("\""+table+"\":[").getBytes(StandardCharsets.UTF_8));
            final boolean[] first={true};
            db.jdbc.query(connection->{var statement=connection.prepareStatement("SELECT * FROM "+table);statement.setFetchSize(100);return statement;},(org.springframework.jdbc.core.RowCallbackHandler)rs->{
                try { if(!first[0]) output.write(',');first[0]=false;output.write(json.writeValueAsString(Store.readRow(rs)).getBytes(StandardCharsets.UTF_8)); }
                catch(IOException e) { throw new UncheckedIOException(e); }
            });
            output.write(']');output.flush();
        }
        output.write('}');
    }
}
