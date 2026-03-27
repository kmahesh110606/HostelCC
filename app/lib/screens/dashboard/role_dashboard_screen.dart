import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../../models/app_models.dart";
import "../../models/user_session.dart";
import "../../services/dashboard_service.dart";

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({
    required this.session,
    required this.dashboardService,
    required this.onLogout,
    super.key,
  });

  final UserSession session;
  final DashboardService dashboardService;
  final Future<void> Function() onLogout;

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  bool _loading = true;
  String? _error;

  List<MessMenu> _menus = <MessMenu>[];
  List<ComplaintItem> _complaints = <ComplaintItem>[];
  List<LaundrySchedule> _schedules = <LaundrySchedule>[];
  List<CatererItem> _caterers = <CatererItem>[];

  final _studentIdController = TextEditingController();
  final _complaintController = TextEditingController();
  final _complaintCategoryController = TextEditingController(text: "PLUMBING");

  final _feedbackMenuItemController = TextEditingController();
  final _feedbackCommentController = TextEditingController();
  final _feedbackRatingController = TextEditingController(text: "4");
  final _pollOptionController = TextEditingController();
  final _messChangeController = TextEditingController();

  final _blockNameController = TextEditingController();
  final _catererNameController = TextEditingController();
  final _catererMealsController = TextEditingController(
    text: "veg, nonveg, special",
  );
  final _catererBlockIdController = TextEditingController();

  final _menuDayController = TextEditingController(text: "MON");
  final _breakfastController = TextEditingController();
  final _lunchController = TextEditingController();
  final _snacksController = TextEditingController();
  final _dinnerController = TextEditingController();
  final _qrStudentIdController = TextEditingController();
  String? _qrPayload;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _complaintController.dispose();
    _complaintCategoryController.dispose();
    _feedbackMenuItemController.dispose();
    _feedbackCommentController.dispose();
    _feedbackRatingController.dispose();
    _pollOptionController.dispose();
    _messChangeController.dispose();
    _blockNameController.dispose();
    _catererNameController.dispose();
    _catererMealsController.dispose();
    _catererBlockIdController.dispose();
    _menuDayController.dispose();
    _breakfastController.dispose();
    _lunchController.dispose();
    _snacksController.dispose();
    _dinnerController.dispose();
    _qrStudentIdController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = widget.session.accessToken;
      final results = await Future.wait([
        widget.dashboardService.getMenus(token),
        widget.dashboardService.getComplaints(token),
        widget.dashboardService.getSchedules(token),
        widget.dashboardService.getCaterers(token),
      ]);

      if (!mounted) return;
      setState(() {
        _menus = results[0] as List<MessMenu>;
        _complaints = results[1] as List<ComplaintItem>;
        _schedules = results[2] as List<LaundrySchedule>;
        _caterers = results[3] as List<CatererItem>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool get _isStudent => widget.session.role == "STUDENT";
  bool get _isWarden => widget.session.role == "WARDEN";
  bool get _isMessManager => widget.session.role == "MESS_MANAGER";
  bool get _isLaundryPerson => widget.session.role == "LAUNDRY_PERSON";
  bool get _isAdmin => widget.session.role == "ADMIN";

  List<_RoleTab> _tabs() {
    final tabs = <_RoleTab>[
      _RoleTab("Community", Icons.forum, _communityTab()),
      _RoleTab("Mess", Icons.restaurant_menu, _messTab()),
      _RoleTab("Laundry", Icons.local_laundry_service, _laundryTab()),
    ];

    if (_isAdmin) {
      tabs.add(_RoleTab("Admin", Icons.admin_panel_settings, _adminTab()));
    }

    return tabs;
  }

  Future<void> _submitComplaint() async {
    final studentId = int.tryParse(_studentIdController.text.trim());
    if (studentId == null || _complaintController.text.trim().isEmpty) {
      _toast("Student ID and complaint text are required");
      return;
    }

    try {
      await widget.dashboardService.submitComplaint(
        token: widget.session.accessToken,
        studentId: studentId,
        category: _complaintCategoryController.text.trim().toUpperCase(),
        text: _complaintController.text.trim(),
      );
      _complaintController.clear();
      _toast("Complaint posted");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _submitFeedback() async {
    final studentId = int.tryParse(_studentIdController.text.trim());
    final rating = int.tryParse(_feedbackRatingController.text.trim()) ?? 4;
    if (studentId == null || _feedbackMenuItemController.text.trim().isEmpty) {
      _toast("Student ID and menu item are required");
      return;
    }

    try {
      await widget.dashboardService.submitFeedback(
        token: widget.session.accessToken,
        studentId: studentId,
        menuItem: _feedbackMenuItemController.text.trim(),
        rating: rating,
        comment: _feedbackCommentController.text.trim(),
        month: DateFormat("yyyy-MM").format(DateTime.now()),
      );
      _feedbackCommentController.clear();
      _feedbackMenuItemController.clear();
      _toast("Feedback submitted");
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _createBlock() async {
    if (_blockNameController.text.trim().isEmpty) {
      _toast("Block name required");
      return;
    }
    try {
      await widget.dashboardService.createBlock(
        token: widget.session.accessToken,
        blockName: _blockNameController.text.trim().toUpperCase(),
      );
      _blockNameController.clear();
      _toast("Block created");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _createCaterer() async {
    final blockId = int.tryParse(_catererBlockIdController.text.trim());
    if (blockId == null || _catererNameController.text.trim().isEmpty) {
      _toast("Caterer name and block ID are required");
      return;
    }

    try {
      await widget.dashboardService.createCaterer(
        token: widget.session.accessToken,
        name: _catererNameController.text.trim(),
        mealTypes: _catererMealsController.text.trim(),
        blockId: blockId,
      );
      _catererNameController.clear();
      _catererBlockIdController.clear();
      _toast("Caterer created");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _createMenu() async {
    try {
      await widget.dashboardService.createMenu(
        token: widget.session.accessToken,
        weekDay: _menuDayController.text.trim().toUpperCase(),
        breakfast: _breakfastController.text.trim(),
        lunch: _lunchController.text.trim(),
        snacks: _snacksController.text.trim(),
        dinner: _dinnerController.text.trim(),
      );
      _toast("Menu created/updated");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _markSubmission(int scheduleId) async {
    try {
      await widget.dashboardService.markLaundrySubmission(
        token: widget.session.accessToken,
        scheduleId: scheduleId,
      );
      _toast("Submission marked (orange)");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _markCollection(int scheduleId) async {
    try {
      await widget.dashboardService.markLaundryCollection(
        token: widget.session.accessToken,
        scheduleId: scheduleId,
      );
      _toast("Collection marked (green)");
      await _loadData();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _fetchQr() async {
    final studentId = int.tryParse(_qrStudentIdController.text.trim());
    if (studentId == null) {
      _toast("Student ID is required");
      return;
    }
    try {
      final payload = await widget.dashboardService.getLaundryQr(
        token: widget.session.accessToken,
        studentId: studentId,
      );
      if (!mounted) return;
      setState(() {
        _qrPayload = payload.toString();
      });
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _votePoll() async {
    final studentId = int.tryParse(_studentIdController.text.trim());
    final optionId = int.tryParse(_pollOptionController.text.trim());
    if (studentId == null || optionId == null) {
      _toast("Student ID and poll option ID are required");
      return;
    }
    try {
      await widget.dashboardService.votePoll(
        token: widget.session.accessToken,
        studentId: studentId,
        optionId: optionId,
      );
      _toast("Vote submitted");
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _requestMessChange() async {
    final studentId = int.tryParse(_studentIdController.text.trim());
    if (studentId == null || _messChangeController.text.trim().isEmpty) {
      _toast("Student ID and requested mess are required");
      return;
    }
    try {
      await widget.dashboardService.requestMessChange(
        token: widget.session.accessToken,
        studentId: studentId,
        requestedMess: _messChangeController.text.trim(),
        month: DateFormat("yyyy-MM").format(DateTime.now()),
      );
      _toast("Mess change request submitted");
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _communityTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Community Threads",
            subtitle: _isWarden
                ? "Warden moderation enabled"
                : "Student community complaints",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _studentIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Student ID",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _complaintCategoryController,
                  decoration: const InputDecoration(
                    labelText:
                        "Category (PLUMBING/ELECTRICAL/CIVIL/WATER/AC/OTHER)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _complaintController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: "Complaint text",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_isStudent || _isWarden || _isAdmin)
                      ? _submitComplaint
                      : null,
                  icon: const Icon(Icons.send),
                  label: const Text("Post Complaint"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ..._complaints.map(
            (c) => Card(
              child: ListTile(
                leading: Icon(
                  c.status == "OPEN" ? Icons.error_outline : Icons.check_circle,
                  color: c.status == "OPEN" ? Colors.orange : Colors.green,
                ),
                title: Text("${c.category} - ${c.status}"),
                subtitle: Text(c.text),
              ),
            ),
          ),
          if (_complaints.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("No complaints available"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _messTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Weekly Menu",
            subtitle: "Mon-Fri breakfast, lunch, snacks, dinner",
            child: Column(
              children: _menus
                  .map(
                    (m) => ListTile(
                      tileColor: const Color(0xFFE8F1FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(
                        m.weekDay,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B3D91),
                        ),
                      ),
                      subtitle: Text(
                        "B: ${m.breakfast}\nL: ${m.lunch}\nS: ${m.snacks}\nD: ${m.dinner}",
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Caterers",
            subtitle: "Block-wise mapping",
            child: Column(
              children: _caterers
                  .map(
                    (c) => ListTile(
                      title: Text(c.name),
                      subtitle: Text("Block ${c.blockName} | ${c.mealTypes}"),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Mess Feedback",
            subtitle: "Students can submit item-wise feedback",
            child: Column(
              children: [
                TextField(
                  controller: _feedbackMenuItemController,
                  decoration: const InputDecoration(
                    labelText: "Menu item",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _feedbackRatingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Rating (1-5)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _feedbackCommentController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Comment",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_isStudent || _isAdmin) ? _submitFeedback : null,
                  icon: const Icon(Icons.reviews),
                  label: const Text("Submit Feedback"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "Poll + Mess Change",
            subtitle: "Vote next month menu item and request mess change",
            child: Column(
              children: [
                TextField(
                  controller: _pollOptionController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Poll option ID",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_isStudent || _isAdmin) ? _votePoll : null,
                  child: const Text("Vote Poll"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _messChangeController,
                  decoration: const InputDecoration(
                    labelText: "Requested mess",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_isStudent || _isAdmin)
                      ? _requestMessChange
                      : null,
                  child: const Text("Request Mess Change"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _laundryTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: "Laundry Schedule",
            subtitle: "Submission orange, collection green",
            child: Column(
              children: _schedules
                  .map(
                    (s) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s.collection
                              ? Colors.green
                              : (s.submission
                                    ? Colors.orange
                                    : const Color(0xFF1976D2)),
                          child: Text(s.day.substring(0, 1)),
                        ),
                        title: Text("Schedule #${s.id} - ${s.day}"),
                        subtitle: Text(
                          "Submission: ${s.submission} | Collection: ${s.collection}",
                        ),
                        trailing: _isLaundryPerson
                            ? Wrap(
                                spacing: 6,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _markSubmission(s.id),
                                    child: const Text("Submit"),
                                  ),
                                  FilledButton(
                                    onPressed: () => _markCollection(s.id),
                                    child: const Text("Collect"),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _sectionCard(
            title: "QR Lookup",
            subtitle: "Get student QR token payload",
            child: Column(
              children: [
                TextField(
                  controller: _qrStudentIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Student ID",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_isLaundryPerson || _isStudent || _isAdmin)
                      ? _fetchQr
                      : null,
                  child: const Text("Fetch QR Data"),
                ),
                if (_qrPayload != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFFE3F2FD),
                    ),
                    child: Text(_qrPayload!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard(
          title: "Create Block",
          subtitle: "You can also manage this in Django admin",
          child: Column(
            children: [
              TextField(
                controller: _blockNameController,
                decoration: const InputDecoration(
                  labelText: "Block name (A/B/C/D1/D2/E)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createBlock,
                child: const Text("Create Block"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: "Create Caterer",
          subtitle: "Enter block ID from backend",
          child: Column(
            children: [
              TextField(
                controller: _catererNameController,
                decoration: const InputDecoration(
                  labelText: "Caterer name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _catererMealsController,
                decoration: const InputDecoration(
                  labelText: "Meal types",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _catererBlockIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Block ID",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createCaterer,
                child: const Text("Create Caterer"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: "Create / Update Menu",
          subtitle: "Weekly day-based menu",
          child: Column(
            children: [
              TextField(
                controller: _menuDayController,
                decoration: const InputDecoration(
                  labelText: "Week day code (MON..FRI)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _breakfastController,
                decoration: const InputDecoration(
                  labelText: "Breakfast",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lunchController,
                decoration: const InputDecoration(
                  labelText: "Lunch",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _snacksController,
                decoration: const InputDecoration(
                  labelText: "Snacks",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dinnerController,
                decoration: const InputDecoration(
                  labelText: "Dinner",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _createMenu,
                child: const Text("Save Menu"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B3D91),
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF2E5FA7))),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleTabs = _tabs();

    return DefaultTabController(
      length: roleTabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text("HostelCC - ${widget.session.role}"),
          bottom: TabBar(
            isScrollable: true,
            tabs: roleTabs
                .map((t) => Tab(text: t.title, icon: Icon(t.icon)))
                .toList(),
          ),
          actions: [
            IconButton(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              tooltip: "Refresh",
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : TabBarView(children: roleTabs.map((t) => t.child).toList()),
      ),
    );
  }
}

class _RoleTab {
  const _RoleTab(this.title, this.icon, this.child);

  final String title;
  final IconData icon;
  final Widget child;
}
