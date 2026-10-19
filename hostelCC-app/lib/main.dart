import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'services/api.dart';
import 'forms.dart';
import 'student_import.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HostelApp());
}

class HostelApp extends StatelessWidget {
  const HostelApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      title: 'HostelCC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff136d55),
              surface: const Color(0xfff8faf6)),
          scaffoldBackgroundColor: const Color(0xfff5f7f3),
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xfff5f7f3),
              surfaceTintColor: Colors.transparent),
          inputDecorationTheme: InputDecorationTheme(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white),
          cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xffe3e9df))))),
      home: const SessionGate());
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final api = Api();
  Map<String, dynamic>? user;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final me = await api.call('/auth/me');
      if (mounted) {
        setState(() => user = Map.from(me));
      }
    } catch (e) {
      if (e is! ApiException || e.status != 401) {
        error =
            'Could not connect to HostelCC. Check your connection and try again.';
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user != null) {
      return Workspace(
          api: api,
          initialUser: user!,
          onSignedOut: () => setState(() => user = null));
    }
    return LoginScreen(
        api: api,
        initialError: error,
        onLogin: (me) => setState(() => user = me));
  }
}

class LoginScreen extends StatefulWidget {
  final Api api;
  final void Function(Map<String, dynamic>) onLogin;
  final String? initialError;
  const LoginScreen(
      {super.key, required this.api, required this.onLogin, this.initialError});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(),
      code = TextEditingController(),
      key = GlobalKey<FormState>();
  bool sent = false, remember = true, busy = false;
  String? error;
  int cooldown = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    error = widget.initialError;
  }

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    timer?.cancel();
    super.dispose();
  }

  Future<void> submit({bool resend = false}) async {
    if (!resend && !key.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!sent || resend) {
        await widget.api.call('/auth/request-code',
            method: 'POST', body: {'email': email.text.trim()});
        if (!mounted) {
          return;
        }
        setState(() {
          sent = true;
          cooldown = 60;
        });
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted || cooldown <= 1) {
            t.cancel();
          }
          if (mounted) {
            setState(() => cooldown = cooldown > 0 ? cooldown - 1 : 0);
          }
        });
      } else {
        final result = await widget.api.call('/auth/verify-code',
            method: 'POST',
            body: {
              'email': email.text.trim(),
              'code': code.text,
              'remember': remember
            });
        if (mounted) {
          widget.onLogin(Map.from(result));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Form(
                          key: key,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.apartment_rounded,
                                    size: 42, color: Color(0xff136d55)),
                                const SizedBox(height: 16),
                                Text('HostelCC.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 38),
                                Text(
                                    sent
                                        ? 'Check your inbox.'
                                        : 'Make yourself at home.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 12),
                                Text(
                                    sent
                                        ? 'If ${email.text} is registered, a six-digit code is on its way. It expires in 10 minutes.'
                                        : 'Your hostel, connected. Sign in with your registered email address.',
                                    style: const TextStyle(
                                        color: Color(0xff7b8f75), height: 1.6)),
                                const SizedBox(height: 28),
                                if (!sent)
                                  TextFormField(
                                      controller: email,
                                      enabled: !busy,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email
                                      ],
                                      decoration: const InputDecoration(
                                          labelText: 'Email address'),
                                      validator: (v) => v != null &&
                                              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                                  .hasMatch(v)
                                          ? null
                                          : 'Enter a valid email')
                                else
                                  TextFormField(
                                      controller: code,
                                      enabled: !busy,
                                      keyboardType: TextInputType.number,
                                      autofillHints: const [
                                        AutofillHints.oneTimeCode
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6)
                                      ],
                                      style: const TextStyle(
                                          fontSize: 24, letterSpacing: 10),
                                      decoration: const InputDecoration(
                                          labelText: 'Verification code'),
                                      validator: (v) => v?.length == 6
                                          ? null
                                          : 'Enter the six-digit code'),
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: remember,
                                    onChanged: busy
                                        ? null
                                        : (v) => setState(() => remember = v!),
                                    title: const Text('Remember me for 30 days',
                                        style: TextStyle(fontSize: 13))),
                                if (error != null)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: Text(error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                        onPressed: busy ? null : submit,
                                        icon: const Icon(Icons.arrow_forward),
                                        label: Text(busy
                                            ? 'Please wait…'
                                            : sent
                                                ? 'Verify & sign in'
                                                : 'Send sign-in code'))),
                                if (sent)
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => setState(() {
                                                      sent = false;
                                                      code.clear();
                                                      error = null;
                                                    }),
                                            child: const Text('Change email')),
                                        TextButton(
                                            onPressed: busy || cooldown > 0
                                                ? null
                                                : () => submit(resend: true),
                                            child: Text(cooldown > 0
                                                ? 'Resend in ${cooldown}s'
                                                : 'Resend code'))
                                      ]),
                                const SizedBox(height: 40),
                                const Row(children: [
                                  Icon(Icons.verified_user_outlined,
                                      size: 19, color: Color(0xff8aa279)),
                                  SizedBox(width: 10),
                                  Expanded(
                                      child: Text(
                                          'No passwords. A secure code, straight to your inbox.',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xff8aa279))))
                                ])
                              ])))))));
}

const sections = <String, (String, IconData)>{
  'overview': ('Overview', Icons.dashboard_outlined),
  'announcements': ('Announcements', Icons.campaign_outlined),
  'users': ('People', Icons.people_outline),
  'blocks': ('Hostel blocks', Icons.apartment),
  'rooms': ('Rooms', Icons.bed_outlined),
  'scopes': ('Duty books', Icons.menu_book_outlined),
  'menus': ('Mess menu', Icons.restaurant_menu),
  'feedback': ('Mess feedback', Icons.rate_review_outlined),
  'polls': ('Polling', Icons.poll_outlined),
  'messChanges': ('Mess changes', Icons.swap_horiz),
  'messes': ('Messes', Icons.restaurant),
  'outings': ('Outings & leave', Icons.directions_walk),
  'discipline': ('Discipline', Icons.shield_outlined),
  'cloakroom': ('Cloakroom records', Icons.inventory_2_outlined),
  'cloakroomRequests': ('My item passes', Icons.qr_code),
  'storageRooms': ('Cloakrooms', Icons.warehouse_outlined),
  'scan': ('Scan item pass', Icons.qr_code_scanner),
  'maintenance': ('Maintenance', Icons.build_outlined),
  'audit': ('Activity & records', Icons.history)
};

class Workspace extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> initialUser;
  final VoidCallback onSignedOut;
  const Workspace(
      {super.key,
      required this.api,
      required this.initialUser,
      required this.onSignedOut});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late Map<String, dynamic> user;
  Map<String, dynamic> data = {};
  String page = 'overview', search = '';
  bool loading = true;
  String? error;
  Timer? searchTimer;
  int pageRequest = 0;
  @override
  void dispose() {
    searchTimer?.cancel();
    super.dispose();
  }

  Future<void> loadPage(String resource, int number, String query) async {
    final request = ++pageRequest;
    try {
      final result = await widget.api.call(
          '/records/$resource?page=$number&size=25&q=${Uri.encodeComponent(query)}');
      if (mounted && request == pageRequest) {
        setState(() {
          data[resource] = result['items'];
          (data['pagination'] as Map)[resource] = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && request == pageRequest) {
        setState(() => error = e.toString());
      }
    }
  }

  bool get admin => user['role'] == 'ADMIN';
  bool get student => user['role'] == 'STUDENT';
  bool get global => admin || user['role'] == 'DIRECTOR';
  @override
  void initState() {
    super.initState();
    user = widget.initialUser;
    refresh();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait(
          [widget.api.call('/auth/me'), widget.api.call('/workspace')]);
      if (mounted) {
        setState(() {
          user = Map.from(results[0]);
          data = Map.from(results[1]);
          error = null;
        });
      }
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        widget.onSignedOut();
      } else if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  bool visible(String p) {
    if (['overview', 'announcements'].contains(p)) {
      return true;
    }
    if (p == 'scan') {
      return has(user, 'CLOAKROOM');
    }
    if (p == 'cloakroomRequests') {
      return student;
    }
    if (global) {
      return true;
    }
    if (['menus', 'feedback', 'polls', 'messChanges'].contains(p)) {
      return student || has(user, 'MESS') || has(user, 'HOSTEL');
    }
    if (['users', 'blocks', 'rooms'].contains(p)) {
      return has(user, 'HOSTEL') ||
          p == 'users' && (has(user, 'OUTINGS') || has(user, 'DISCIPLINE'));
    }
    if (p == 'outings') {
      return student || has(user, 'OUTINGS');
    }
    if (p == 'discipline') {
      return student || has(user, 'DISCIPLINE');
    }
    if (['cloakroom', 'storageRooms'].contains(p)) {
      return student || has(user, 'CLOAKROOM');
    }
    if (p == 'maintenance') {
      return student || has(user, 'MAINTENANCE');
    }
    return p == 'audit' && !student;
  }

  String resource(String p) =>
      {
        'storageRooms': 'storage-rooms',
        'messChanges': 'mess-changes',
        'cloakroomRequests': 'cloakroom/request'
      }[p] ??
      p;
  bool canCreate(String p) {
    if (['overview', 'audit', 'cloakroom', 'scan'].contains(p)) {
      return false;
    }
    if (p == 'feedback') {
      return student;
    }
    if (p == 'cloakroomRequests') {
      return student && user['cloakroomAccess'] == true;
    }
    if (p == 'messChanges') {
      return student && user['messChangeAccess'] == true;
    }
    if (admin) {
      return true;
    }
    if (p == 'announcements') {
      return has(user, 'HOSTEL');
    }
    if (['menus', 'polls'].contains(p)) {
      return has(user, 'MESS');
    }
    if (p == 'outings') {
      return student || has(user, 'OUTINGS');
    }
    if (p == 'discipline') {
      return has(user, 'DISCIPLINE');
    }
    return p == 'maintenance' &&
        (student || has(user, 'MAINTENANCE') && user['role'] != 'HOUSEKEEPING');
  }

  Future<void> edit(String p, [Map<String, dynamic>? row]) async {
    final r = resource(p), update = row != null && p != 'menus';
    final initial = <String, dynamic>{
      'active': true,
      'role': 'STUDENT',
      'book': 'HOSTEL',
      'roomType': 'NON_AC',
      'kind': 'OUTING',
      'audience': 'ALL',
      'level': 'INFO',
      'day': 'MON',
      'meal': 'LUNCH',
      'mealDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'rating': '5',
      'itemType': 'CHAIR',
      'capacity': 2,
      'tokenStart': 1,
      'tokenEnd': 1000,
      'blockIds': <String>[],
      'messId': user['messId'] ?? '',
      ...?row
    };
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title:
                    '${row == null ? 'Add' : 'Edit'} ${sections[p]?.$1 ?? label(p)}',
                path: '/$r${update ? '/${row['id']}' : ''}',
                method: update ? 'PUT' : 'POST',
                api: widget.api,
                initial: initial,
                fields: (values) => withLookups(
                    resourceFields(r, data, user, values, row != null),
                    r,
                    values,
                    data))));
    if (saved == true) {
      await refresh();
    }
  }

  Future<void> action(String p, Map<String, dynamic> row, String action,
      {List<Field> fields = const [],
      Map<String, dynamic> initial = const {},
      String? path}) async {
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title: label(action),
                path: path ?? '/${resource(p)}/${row['id']}/action',
                api: widget.api,
                initial: {'action': action, ...initial},
                fields: (_) => fields)));
    if (saved == true) {
      await refresh();
    }
  }

  List<Widget> actions(String p, Map<String, dynamic> row) {
    TextButton button(String title, VoidCallback onTap) =>
        TextButton(onPressed: onTap, child: Text(title));
    const note = Field('note', 'Note', type: 'long');
    return [
      if (admin &&
          ['users', 'blocks', 'rooms', 'messes', 'storageRooms', 'scopes']
              .contains(p))
        button('Edit', () => edit(p, row)),
      if (p == 'announcements' && has(user, 'HOSTEL', row['blockId']))
        button('Edit', () => edit(p, row)),
      if (p == 'menus' && has(user, 'MESS', row['messId']))
        button('Edit menu', () => edit(p, row)),
      if (p == 'feedback' && has(user, 'MESS', row['messId']))
        button(
            'Reply',
            () => action(p, row, 'reply',
                fields: [const Field('reply', 'Reply', type: 'long')],
                initial: {'reply': row['reply']})),
      if (p == 'outings') ...[
        if (has(user, 'OUTINGS', row['blockId'])) ...[
          if (row['status'] == 'PENDING') ...[
            button(
                'Approve',
                () => action(p, row, 'approve', fields: [
                      const Field('note', 'Note', type: 'long', optional: true)
                    ])),
            button('Reject', () => action(p, row, 'reject', fields: [note]))
          ],
          if (row['status'] == 'APPROVED')
            button('Record exit', () => action(p, row, 'exit')),
          if (row['status'] == 'OUT')
            button('Record entry', () => action(p, row, 'enter')),
        ],
        if ((student || has(user, 'OUTINGS', row['blockId'])) &&
            ['PENDING', 'APPROVED'].contains(row['status']))
          button(
              'Cancel',
              () => action(p, row, 'cancel',
                  fields: [const Field('note', 'Note', optional: true)])),
      ],
      if (p == 'discipline' &&
          row['cardHeld'] == true &&
          row['cardReturnedAt'] == null &&
          has(user, 'DISCIPLINE', row['blockId']))
        button(
            'Return ID', () => action(p, row, 'return card', fields: [note])),
      if (p == 'messChanges' && admin && row['status'] == 'PENDING')
        for (final name in ['approve', 'reject'])
          button(
              label(name),
              () => action(p, row, name,
                  fields: [const Field('note', 'Note', optional: true)])),
      if (p == 'cloakroom' &&
          row['status'] == 'STORED' &&
          has(user, 'CLOAKROOM', row['storageId'])) ...[
        button(
            'Return',
            () => action(p, row, 'return', fields: [
                  const Field('receipt', 'Full receipt reference'),
                  note
                ])),
        button(
            'Relocate',
            () => action(p, row, 'move', fields: [
                  Field('storageId', 'Target room',
                      type: 'select',
                      options: rows(data, 'storageRooms')
                          .where((r) =>
                              r['active'] == true &&
                              r['id'] != row['storageId'] &&
                              r['blockId'] == row['blockId'] &&
                              r['itemType'] == row['item'] &&
                              has(user, 'CLOAKROOM', r['id']))
                          .map(
                              (r) => (r['id'].toString(), r['name'].toString()))
                          .toList()),
                  note
                ])),
      ],
      if (p == 'maintenance' && has(user, 'MAINTENANCE', row['blockId'])) ...[
        if (user['role'] != 'HOUSEKEEPING' && row['status'] != 'RESOLVED')
          button(
              'Assign',
              () => action(p, row, 'assign', fields: [
                    Field('assigneeId', 'Housekeeping staff',
                        remote: '/options/housekeeping?block=${Uri.encodeComponent(row['blockId'].toString())}',
                        type: 'select',
                        options: rows(data, 'users')
                            .where((u) =>
                                u['active'] == true &&
                                u['role'] == 'HOUSEKEEPING' &&
                                (u['maintenanceBlockIds'] as List? ?? [])
                                    .contains(row['blockId']))
                            .map((u) =>
                                (u['id'].toString(), u['name'].toString()))
                            .toList())
                  ])),
        if (row['status'] == 'OPEN' && row['assigneeId'] != null)
          button('Start', () => action(p, row, 'start')),
        if (row['status'] == 'IN_PROGRESS')
          button(
              'Resolve',
              () => action(p, row, 'resolve', fields: [
                    const Field('resolution', 'Work completed', type: 'long')
                  ])),
        if (row['status'] == 'RESOLVED' && user['role'] != 'HOUSEKEEPING')
          button('Reopen', () => action(p, row, 'reopen')),
      ],
    ];
  }

  String display(dynamic v, [String key = '']) {
    if (v == null || v == '') {
      return '—';
    }
    if (v is bool) {
      return v ? 'Yes' : 'No';
    }
    if (key.endsWith('At') && v is String) {
      final date = DateTime.tryParse(v);
      if (date != null) {
        return DateFormat.yMMMd().add_jm().format(date.toLocal());
      }
    }
    return v.toString();
  }

  Widget status(dynamic value) => Chip(
      label: Text(label(value), style: const TextStyle(fontSize: 11)),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xffedf2e6));
  Widget record(String p, Map<String, dynamic> row) {
    final title = row['title'] ??
        row['name'] ??
        row['studentName'] ??
        row['category'] ??
        row['action'] ??
        row['number'] ??
        label(p);
    return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(title.toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16))),
                if (row['status'] != null || row['level'] != null)
                  status(row['overdue'] == true
                      ? 'OVERDUE'
                      : row['status'] ?? row['level'])
              ]),
              const SizedBox(height: 10),
              for (final key in previewKeys(p))
                if (row[key] != null && row[key] != '')
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${label(key)}: ${display(row[key], key)}',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xff74816c),
                              height: 1.5))),
              Wrap(spacing: 6, children: [
                TextButton(
                    onPressed: () => showDetails(row),
                    child: const Text('Details')),
                ...actions(p, row)
              ])
            ])));
  }

  List<String> previewKeys(String p) => switch (p) {
        'announcements' => ['body', 'createdAt'],
        'menus' => [
            'messName',
            'day',
            'breakfast',
            'lunch',
            'snacks',
            'dinner'
          ],
        'feedback' => [
            'messName',
            'meal',
            'mealDate',
            'rating',
            'comment',
            'reply'
          ],
        'outings' => [
            'kind',
            'destination',
            'departureAt',
            'expectedReturnAt',
            'exitedAt',
            'enteredAt'
          ],
        'discipline' => [
            'violation',
            'occurrenceNumber',
            'actionTaken',
            'cardHeld'
          ],
        'cloakroom' => ['item', 'tokenNumber', 'storageName', 'receipt'],
        'storageRooms' => [
            'blockName',
            'itemType',
            'occupied',
            'capacity',
            'tokenStart',
            'tokenEnd',
            'nextToken'
          ],
        'maintenance' => [
            'blockName',
            'roomLabel',
            'description',
            'assigneeName',
            'resolution'
          ],
        'scopes' => ['userName', 'book', 'targetName', 'active'],
        'users' => ['email', 'role', 'rollNo', 'blockName', 'roomNumber'],
        'rooms' => ['blockName', 'roomType', 'occupied', 'capacity'],
        'blocks' => ['contactEmail', 'contactPhone', 'active'],
        'messes' => ['occupied', 'capacity', 'active'],
        'audit' => ['actorName', 'detail', 'createdAt'],
        'messChanges' => ['messName', 'decisionNote', 'createdAt'],
        _ => ['createdAt']
      };
  void showDetails(Map<String, dynamic> row) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .75,
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Text('Record details',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  for (final e in row.entries)
                    if (e.value != null &&
                        e.value != '' &&
                        !e.key.endsWith('Id') &&
                        !['id', 'blockIds', 'scopes'].contains(e.key))
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label(e.key),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xff8a997e))),
                                const SizedBox(height: 5),
                                SelectableText(display(e.value, e.key))
                              ]))
                ]))));
  }

  Widget overview() {
    final stats = data['stats'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
              color: const Color(0xffe8f0df),
              borderRadius: BorderRadius.circular(18)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                style: const TextStyle(color: Color(0xff789365), fontSize: 12)),
            const SizedBox(height: 14),
            Text('Welcome back,\n${user['name'].toString().split(' ').first}.',
                style: const TextStyle(
                    fontSize: 29, fontWeight: FontWeight.w600, height: 1.2)),
            const SizedBox(height: 12),
            const Text('Your day on campus, a little more organised.',
                style: TextStyle(color: Color(0xff859776))),
            const SizedBox(height: 12),
            Text(
                user['blockName'] ??
                    (global ? 'All hostel blocks' : 'Your assigned duty books'),
                style: const TextStyle(fontSize: 12))
          ])),
      const SizedBox(height: 20),
      LayoutBuilder(
          builder: (_, constraints) =>
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final stat in [
                  (
                    student ? 'Your room' : 'Students in scope',
                    student ? user['roomNumber'] ?? '—' : stats['students'] ?? 0
                  ),
                  ('Currently outside', stats['studentsOut'] ?? 0),
                  ('Stored items', stats['storedItems'] ?? 0),
                  ('Open requests', stats['openTasks'] ?? 0)
                ])
                  SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(stat.$1,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xff8c9b81))),
                                    const SizedBox(height: 14),
                                    Text('${stat.$2}',
                                        style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w600))
                                  ]))))
              ])),
      const SizedBox(height: 25),
      Text('Notice board', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      if (rows(data, 'announcements').isEmpty)
        const EmptyState(
            title: 'All caught up',
            subtitle: 'New announcements will appear here.'),
      for (final row in rows(data, 'announcements').take(3))
        record('announcements', row),
      if (student)
        Wrap(spacing: 12, children: [
          FilledButton.icon(
              onPressed: () => edit('outings'),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Request outing')),
          OutlinedButton.icon(
              onPressed: () => edit('maintenance'),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Report repair'))
        ])
    ]);
  }

  Widget poll(Map<String, dynamic> p) {
    final open = p['enabled'] == true &&
        DateTime.parse(p['closesAt']).isAfter(DateTime.now());
    final voted = (p['myVote'] ?? '') != '';
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['messName'],
                  style: const TextStyle(color: Color(0xff81966f))),
              const SizedBox(height: 10),
              Text(p['title'], style: Theme.of(context).textTheme.titleLarge),
              Text('Closes ${display(p['closesAt'], 'closesAt')}',
                  style: const TextStyle(fontSize: 12)),
              status(open ? 'OPEN' : 'CLOSED'),
              for (final o in p['options'])
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: OutlinedButton(
                        onPressed: student && open && !voted
                            ? () => action('polls', p, 'Vote for ${o['label']}',
                                initial: {'optionId': o['id']})
                            : null,
                        child: Row(children: [
                          Expanded(child: Text(o['label'])),
                          if (o['id'] == p['myVote'])
                            const Icon(Icons.check_circle_outline, size: 17),
                          Text('${o['votes']} votes')
                        ]))),
              if (has(user, 'MESS', p['messId']))
                TextButton(
                    onPressed: () => action(
                        'polls', p, open ? 'Disable voting' : 'Enable voting',
                        path: '/polls/${p['id']}/state',
                        initial: {'enabled': p['enabled'] != true}),
                    child: Text(p['enabled'] == true
                        ? 'Disable voting'
                        : 'Enable voting'))
            ])));
  }

  Widget pass(Map<String, dynamic> q) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text('${label(q['item'])} · ${q['storageName']}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            QrImageView(
                data: q['qrToken'], size: 220, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            Text(
                q['tokenNumber'] == null
                    ? 'Ready for staff to scan'
                    : 'Token ${q['tokenNumber']}',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            Text('${user['name']} · ${user['rollNo']}'),
            status(q['entryStatus'] ?? q['state']),
            TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: q['qrToken']));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Item-pass code copied')));
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy pass code')),
            if (q['state'] == 'PENDING')
              TextButton(
                  onPressed: () => action(
                      'cloakroomRequests', q, 'Cancel unused pass',
                      path: '/cloakroom/requests/${q['id']}/cancel'),
                  child: const Text('Cancel unused pass'))
          ])));
  Future<void> export() async {
    try {
      final records = await widget.api.call('/admin/export');
      final bytes = Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(records)));
      await Share.shareXFiles([
        XFile.fromData(bytes,
            mimeType: 'application/json', name: 'hostelcc-records.json')
      ], fileNameOverrides: [
        'hostelcc-records.json'
      ], subject: 'HostelCC records');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = sections.entries.where((e) => visible(e.key)).toList();
    final entries = rows(data, page).map((r) {
      r['storageName'] ??= rows(data, 'storageRooms')
          .where((s) => s['id'] == r['storageId'])
          .firstOrNull?['name'];
      r['messName'] ??= rows(data, 'messes')
          .where((m) => m['id'] == r['messId'])
          .firstOrNull?['name'];
      r['targetName'] ??= [
        ...rows(data, 'blocks'),
        ...rows(data, 'messes'),
        ...rows(data, 'storageRooms')
      ].where((t) => t['id'] == r['targetId']).firstOrNull?['name'];
      return r;
    }).toList();
    final meta = (data['pagination'] as Map?)?[page] as Map? ?? {};
    final pageNumber = meta['page'] as int? ?? 0,
        total = meta['total'] as int? ?? 0;
    return Scaffold(
        appBar: AppBar(title: Text(sections[page]!.$1), actions: [
          if (admin && page == 'users')
            IconButton(
                tooltip: 'Import CSV',
                icon: const Icon(Icons.upload_file),
                onPressed: () async {
                  final saved = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              StudentImportScreen(api: widget.api)));
                  if (saved == true) await refresh();
                }),
          IconButton(
              tooltip: 'Refresh',
              onPressed: refresh,
              icon: const Icon(Icons.refresh)),
          if (admin && page == 'audit')
            IconButton(
                tooltip: 'Export records',
                onPressed: export,
                icon: const Icon(Icons.file_download_outlined))
        ]),
        drawer: Drawer(
            child: SafeArea(
                child: Column(children: [
          ListTile(
              leading: const Icon(Icons.apartment, size: 32),
              title: const Text('HostelCC.',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
              subtitle: Text('${user['name']} · ${label(user['role'])}')),
          const Divider(),
          Expanded(
              child: ListView(children: [
            for (final e in destinations)
              ListTile(
                  leading: Icon(e.value.$2),
                  title: Text(e.value.$1),
                  selected: page == e.key,
                  selectedTileColor: const Color(0xffe9f1df),
                  onTap: () {
                    setState(() {
                      page = e.key;
                      search = '';
                    });
                    Navigator.pop(context);
                    searchTimer?.cancel();
                    if (!['overview', 'scan'].contains(e.key)) {
                      loadPage(e.key, 0, '');
                    }
                  })
          ])),
          ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                try {
                  await widget.api
                      .call('/auth/logout', method: 'POST', body: {});
                  widget.onSignedOut();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              })
        ]))),
        floatingActionButton: !loading && canCreate(page)
            ? FloatingActionButton.extended(
                onPressed: () => edit(page),
                icon: const Icon(Icons.add),
                label: Text(page == 'cloakroomRequests' ? 'Item pass' : 'Add'))
            : null,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : !visible(page)
                ? const EmptyState(
                    title: 'Assignment changed',
                    subtitle: 'Choose another duty from the menu.')
                : page == 'scan'
                    ? ScanScreen(
                        api: widget.api,
                        data: data,
                        user: user,
                        onProcessed: refresh)
                    : RefreshIndicator(
                        onRefresh: refresh,
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 820),
                                child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 16, 20, 100),
                                    children: [
                                      if (error != null)
                                        MaterialBanner(
                                            content: Text(error!),
                                            actions: [
                                              TextButton(
                                                  onPressed: refresh,
                                                  child: const Text('Retry'))
                                            ]),
                                      if (page == 'overview')
                                        overview()
                                      else ...[
                                        if (page == 'cloakroomRequests')
                                          const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 18),
                                              child: Text(
                                                  'Generate one pass per item. Submit your chair first, then show each pass to the staff assigned to its room.')),
                                        TextField(
                                            key: ValueKey(page),
                                            decoration: const InputDecoration(
                                                hintText: 'Search records',
                                                prefixIcon: Icon(Icons.search)),
                                            onChanged: (v) {
                                              setState(() => search = v);
                                              searchTimer?.cancel();
                                              final resource = page;
                                              searchTimer = Timer(
                                                  const Duration(
                                                      milliseconds: 300),
                                                  () =>
                                                      loadPage(resource, 0, v));
                                            }),
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  '$total records ? Page ${pageNumber + 1}')),
                                          IconButton(
                                              tooltip: 'Previous page',
                                              onPressed: pageNumber == 0
                                                  ? null
                                                  : () => loadPage(page,
                                                      pageNumber - 1, search),
                                              icon: const Icon(
                                                  Icons.chevron_left)),
                                          IconButton(
                                              tooltip: 'Next page',
                                              onPressed:
                                                  (pageNumber + 1) * 25 >= total
                                                      ? null
                                                      : () => loadPage(
                                                          page,
                                                          pageNumber + 1,
                                                          search),
                                              icon: const Icon(
                                                  Icons.chevron_right))
                                        ]),
                                        const SizedBox(height: 20),
                                        if (entries.isEmpty)
                                          const EmptyState(
                                              title: 'No records yet',
                                              subtitle:
                                                  'Records in your assigned scope will appear here.'),
                                        for (final row in entries)
                                          page == 'polls'
                                              ? poll(row)
                                              : page == 'cloakroomRequests'
                                                  ? pass(row)
                                                  : record(page, row)
                                      ]
                                    ])))));
  }
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  const EmptyState({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      child: Column(children: [
        const Icon(Icons.inbox_outlined, size: 38, color: Color(0xff99ac88)),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff8b9d7e)))
      ]));
}

class ScanScreen extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> data, user;
  final Future<void> Function() onProcessed;
  const ScanScreen(
      {super.key,
      required this.api,
      required this.data,
      required this.user,
      required this.onProcessed});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final qr = TextEditingController(), notes = TextEditingController();
  String? room;
  String mode = 'submit', condition = 'GOOD';
  bool camera = false, busy = false;
  String? error;
  Map<String, dynamic>? receipt;
  @override
  void dispose() {
    qr.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> process() async {
    if (room == null || qr.text.trim().isEmpty) {
      setState(() => error = 'Choose a room and scan an item pass.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      camera = false;
      receipt = null;
    });
    try {
      final result =
          await widget.api.call('/cloakroom/scan', method: 'POST', body: {
        'storageId': room,
        'qrToken': qr.text.trim(),
        'mode': mode,
        'itemCondition': condition,
        'notes': notes.text.trim()
      });
      if (mounted) {
        setState(() {
          receipt = Map.from(result);
          qr.clear();
          notes.clear();
        });
      }
      await widget.onProcessed();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(22), children: [
        const Text(
            'Choose your assigned room, scan the item pass, and confirm the operation.',
            style: TextStyle(height: 1.6)),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
            initialValue: room,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cloakroom'),
            items: rows(widget.data, 'storageRooms')
                .where((r) =>
                    r['active'] == true &&
                    has(widget.user, 'CLOAKROOM', r['id']))
                .map((r) => DropdownMenuItem(
                    value: r['id'].toString(),
                    child: Text('${r['name']} · ${label(r['itemType'])}',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => room = v)),
        const SizedBox(height: 16),
        SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'submit', label: Text('Check in')),
              ButtonSegment(value: 'return', label: Text('Return item'))
            ],
            selected: {
              mode
            },
            onSelectionChanged:
                busy ? null : (v) => setState(() => mode = v.first)),
        const SizedBox(height: 16),
        if (camera)
          SizedBox(
              height: 260,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                      onDetect: (capture) {
                        if (!camera) {
                          return;
                        }
                        final value = capture.barcodes.firstOrNull?.rawValue;
                        if (value != null) {
                          setState(() {
                            qr.text = value;
                            camera = false;
                          });
                        }
                      },
                      errorBuilder: (_, e, child) => const Center(
                          child: Text(
                              'Camera unavailable. Allow camera access, or paste the item-pass code.'))))),
        OutlinedButton.icon(
            onPressed: busy ? null : () => setState(() => camera = !camera),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(camera ? 'Stop camera' : 'Open camera')),
        const SizedBox(height: 12),
        TextField(
            controller: qr,
            enabled: !busy,
            decoration: const InputDecoration(
                labelText: 'Item-pass code', hintText: 'HCC1:…')),
        if (mode == 'submit')
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration:
                      const InputDecoration(labelText: 'Item condition'),
                  items: const [
                    DropdownMenuItem(
                        value: 'GOOD', child: Text('Good condition')),
                    DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged'))
                  ],
                  onChanged:
                      busy ? null : (v) => setState(() => condition = v!))),
        const SizedBox(height: 16),
        TextField(
            controller: notes,
            enabled: !busy,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: mode == 'return'
                    ? 'Collection note (required)'
                    : 'Notes (optional)')),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: busy ? null : process,
            icon: const Icon(Icons.check),
            label: Text(busy
                ? 'Processing…'
                : mode == 'submit'
                    ? 'Check in & issue token'
                    : 'Confirm collection')),
        if (receipt != null)
          Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: Column(children: [
                        const Icon(Icons.check_circle_outline,
                            size: 36, color: Color(0xff438053)),
                        const SizedBox(height: 12),
                        Text('Token ${receipt!['tokenNumber']}',
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.w600)),
                        Text(receipt!['studentName'] ?? ''),
                        Text(
                            '${label(receipt!['item'])} · ${label(receipt!['status'])}'),
                        const SizedBox(height: 14),
                        SelectableText(receipt!['receipt'],
                            style: const TextStyle(fontSize: 11))
                      ]))))
      ]);
}
