import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/api.dart';
import 'remote_options.dart';

class Field {
  final String keyName, title, type;
  final bool optional;
  final String? remote;
  final List<(String, String)> options;
  const Field(this.keyName, this.title,
      {this.type = 'text',
      this.optional = false,
      this.options = const [],
      this.remote});
}

const roles = [
  'ADMIN',
  'DIRECTOR',
  'WARDEN',
  'SUPERVISOR',
  'STUDENT',
  'MESS_MANAGER',
  'HOUSEKEEPING'
];
List<(String, String)> choices(List<String> values) =>
    values.map((v) => (v, label(v))).toList();
List<Field> resourceFields(String resource, Map<String, dynamic> data,
    Map<String, dynamic> user, Map<String, dynamic> values, bool editing) {
  List<(String, String)> options(String key,
          [bool Function(Map<String, dynamic>)? filter]) =>
      rows(data, key)
          .where(filter ?? (_) => true)
          .map((r) => (
                r['id'].toString(),
                [
                  r['name'] ?? r['number'] ?? r['studentName'],
                  r['blockName'],
                  r['rollNo']
                ].where((s) => s != null && s != '').join(' · ')
              ))
          .toList();
  Field select(String key, String title, List<(String, String)> opts,
          {bool optional = false}) =>
      Field(key, title, type: 'select', options: opts, optional: optional);
  final blocks = options('blocks', (b) => b['active'] == true);
  final messes = options(
      'messes',
      (m) =>
          m['active'] == true &&
          (user['role'] == 'STUDENT' || has(user, 'MESS', m['id'])));
  final students = options(
      'users',
      (u) =>
          u['active'] == true &&
          u['role'] == 'STUDENT' &&
          (has(user, resource == 'discipline' ? 'DISCIPLINE' : 'OUTINGS',
              u['blockId'])));
  final active =
      editing ? [const Field('active', 'Active', type: 'bool')] : <Field>[];
  switch (resource) {
    case 'blocks':
      return [
        const Field('name', 'Block name'),
        const Field('contactEmail', 'Contact email', optional: true),
        const Field('contactPhone', 'Contact phone', optional: true),
        ...active
      ];
    case 'rooms':
      return [
        select('blockId', 'Block', blocks),
        const Field('number', 'Room number'),
        const Field('capacity', 'Beds', type: 'number'),
        select('roomType', 'Room type', choices(['AC', 'NON_AC'])),
        ...active
      ];
    case 'messes':
      return [
        const Field('name', 'Mess name'),
        const Field('capacity', 'Capacity', type: 'number'),
        Field('blockIds', 'Blocks served',
            type: 'multi', options: blocks, remote: '/options/blocks'),
        ...active
      ];
    case 'users':
      return [
        const Field('name', 'Full name'),
        const Field('email', 'Email', type: 'email'),
        select('role', 'Role', choices(roles)),
        const Field('phone', 'Phone', optional: true),
        if (values['role'] == 'STUDENT') ...[
          const Field('rollNo', 'Roll number'),
          select('blockId', 'Block', blocks),
          select(
              'roomId',
              'Room',
              options(
                  'rooms',
                  (r) =>
                      r['active'] == true && r['blockId'] == values['blockId']),
              optional: true),
          select(
              'messId',
              'Mess',
              options(
                  'messes',
                  (m) =>
                      m['active'] == true &&
                      (m['blockIds'] as List).contains(values['blockId'])),
              optional: true),
          const Field('cloakroomAccess', 'Enable cloakroom passes',
              type: 'bool'),
        ] else if (values['role'] == 'MESS_MANAGER')
          select('messId', 'Primary mess',
              options('messes', (m) => m['active'] == true)),
        ...active
      ];
    case 'scopes':
      return [
        select(
            'userId',
            'Staff member',
            options(
                'users',
                (u) =>
                    u['active'] == true &&
                    !['ADMIN', 'DIRECTOR', 'STUDENT'].contains(u['role']))),
        select(
            'book',
            'Duty book',
            choices([
              'HOSTEL',
              'MESS',
              'OUTINGS',
              'DISCIPLINE',
              'MAINTENANCE',
              'CLOAKROOM'
            ])),
        select(
            'targetId',
            'Assigned location',
            options(
                values['book'] == 'MESS'
                    ? 'messes'
                    : values['book'] == 'CLOAKROOM'
                        ? 'storageRooms'
                        : 'blocks',
                (r) => r['active'] == true)),
        const Field('active', 'Assignment enabled', type: 'bool')
      ];
    case 'announcements':
      return [
        const Field('title', 'Title'),
        const Field('body', 'Announcement', type: 'long'),
        select('level', 'Priority', choices(['INFO', 'WARNING', 'URGENT'])),
        select('audience', 'Audience', choices(['ALL', ...roles])),
        select('blockId', 'Block',
            blocks.where((b) => has(user, 'HOSTEL', b.$1)).toList(),
            optional: user['role'] == 'ADMIN'),
        ...active
      ];
    case 'menus':
      return [
        select('messId', 'Mess', messes),
        select('day', 'Day',
            choices(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])),
        for (final meal in ['breakfast', 'lunch', 'snacks', 'dinner'])
          Field(meal, label(meal), type: 'long')
      ];
    case 'polls':
      return [
        select('messId', 'Mess', messes),
        const Field('title', 'Question'),
        const Field('closesAt', 'Closes at', type: 'datetime'),
        const Field('options', 'Options (one per line)', type: 'lines')
      ];
    case 'outings':
      return [
        if (user['role'] != 'STUDENT') select('studentId', 'Student', students),
        select(
            'kind', 'Request type', choices(['OUTING', 'LEAVE', 'NIGHT_MESS'])),
        const Field('destination', 'Destination'),
        const Field('reason', 'Reason', type: 'long'),
        const Field('departureAt', 'Departure', type: 'datetime'),
        const Field('expectedReturnAt', 'Expected return', type: 'datetime')
      ];
    case 'discipline':
      return [
        select('studentId', 'Student', students),
        const Field('violation', 'Violation'),
        const Field('actionTaken', 'Action taken'),
        const Field('notes', 'Details', type: 'long', optional: true),
        const Field('cardHeld', 'Hold ID card', type: 'bool')
      ];
    case 'storage-rooms':
      return [
        const Field('name', 'Cloakroom name'),
        select('blockId', 'Block', blocks),
        select(
            'itemType',
            'Item type',
            choices([
              'CHAIR',
              'BUCKET',
              'CARTON',
              'SUITCASE',
              'MATTRESS',
              'OTHER'
            ])),
        const Field('capacity', 'Capacity', type: 'number'),
        const Field('tokenStart', 'First token', type: 'number'),
        const Field('tokenEnd', 'Last token', type: 'number'),
        ...active
      ];
    case 'cloakroom/request':
      return [
        if (user['role'] == 'ADMIN')
          select(
              'studentId',
              'Student',
              options('users',
                  (u) => u['role'] == 'STUDENT' && u['active'] == true)),
        select(
            'storageId',
            'Room and item type',
            rows(data, 'storageRooms')
                .where((r) => r['active'] == true)
                .map((r) => (
                      r['id'].toString(),
                      '${r['name']} · ${label(r['itemType'])}'
                    ))
                .toList())
      ];
    case 'maintenance':
      return [
        if (user['role'] != 'STUDENT') ...[
          select('blockId', 'Block',
              blocks.where((b) => has(user, 'MAINTENANCE', b.$1)).toList()),
          const Field('roomLabel', 'Room / location', optional: true)
        ],
        select(
            'category',
            'Category',
            choices([
              'CLEANING',
              'PLUMBING',
              'ELECTRICAL',
              'CARPENTRY',
              'WATER',
              'AC',
              'OTHER'
            ])),
        const Field('description', 'What needs attention?', type: 'long')
      ];
    default:
      return [];
  }
}

class RecordForm extends StatefulWidget {
  final String title, path, method;
  final Api api;
  final Map<String, dynamic> initial;
  final Map<String, dynamic> Function(Map<String, dynamic>)? transform;
  final List<Field> Function(Map<String, dynamic>) fields;
  const RecordForm(
      {super.key,
      required this.title,
      required this.path,
      required this.api,
      required this.fields,
      this.method = 'POST',
      this.transform,
      this.initial = const {}});
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final _key = GlobalKey<FormState>();
  late Map<String, dynamic> values;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    values = Map.of(widget.initial);
  }

  Future<void> save() async {
    if (!_key.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = Map<String, dynamic>.of(values);
      for (final f in widget.fields(values)) {
        if (f.type == 'number') {
          body[f.keyName] = int.parse('${body[f.keyName]}');
        }
        if (f.type == 'lines') {
          body[f.keyName] = '${body[f.keyName]}'
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
      await widget.api.call(widget.path,
          method: widget.method, body: widget.transform?.call(body) ?? body);
      if (mounted) {
        Navigator.pop(context, true);
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

  Future<void> pickDate(Field f) async {
    final current =
        DateTime.tryParse('${values[f.keyName] ?? ''}')?.toLocal() ??
            DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (date == null || !mounted) {
      return;
    }
    if (f.type == 'date') {
      setState(() => values[f.keyName] = DateFormat('yyyy-MM-dd').format(date));
      return;
    }
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time != null && mounted) {
      setState(() => values[f.keyName] =
          DateTime(date.year, date.month, date.day, time.hour, time.minute)
              .toUtc()
              .toIso8601String());
    }
  }

  Widget field(Field f) {
    final value = values[f.keyName];
    if (f.remote != null && f.type == 'multi') {
      final ids = List<String>.from(value ?? []);
      return Column(children: [
        RemoteOption(
            api: widget.api,
            path: f.remote!,
            title: 'Add block',
            optional: true,
            onSelected: (o) {
              final id = o?['value'];
              if (id != null && !ids.contains(id)) {
                setState(() => values[f.keyName] = [...ids, id]);
              }
            }),
        for (final id in ids)
          Row(children: [
            Expanded(
                child: RemoteOption(
                    api: widget.api,
                    path: f.remote!,
                    title: 'Block',
                    value: id,
                    onSelected: (o) {
                      if (o != null) {
                        setState(() => values[f.keyName] = ids
                            .map((v) => v == id ? o['value'] : v)
                            .toSet()
                            .toList());
                      }
                    })),
            IconButton(
                tooltip: 'Remove block',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() =>
                    values[f.keyName] = ids.where((v) => v != id).toList()))
          ])
      ]);
    }
    if (f.remote != null) {
      return RemoteOption(
          api: widget.api,
          path: f.remote!,
          title: f.title,
          value: value?.toString(),
          optional: f.optional,
          onSelected: (option) => setState(() {
                values[f.keyName] = option?['value'] ?? '';
                if (f.keyName == 'blockId') {
                  values['roomId'] = '';
                  values['messId'] = '';
                }
                if (f.keyName == 'bookId') {
                  values['book'] = option?['baseBook'] ?? values['book'];
                  values['targetId'] = '';
                }
                if (f.keyName == 'studentId') {
                  values['studentBlockId'] = option?['blockId'];
                  values['storageId'] = '';
                }
              }));
    }
    if (f.type == 'bool') {
      return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.title),
          value: value == true,
          onChanged:
              busy ? null : (v) => setState(() => values[f.keyName] = v));
    }
    if (f.type == 'multi') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.title),
        Wrap(
            spacing: 8,
            children: f.options
                .map((o) => FilterChip(
                    label: Text(o.$2),
                    selected: (value as List? ?? []).contains(o.$1),
                    onSelected: busy
                        ? null
                        : (selected) => setState(() {
                              final items = List<String>.from(value ?? []);
                              if (selected) {
                                items.add(o.$1);
                              } else {
                                items.remove(o.$1);
                              }
                              values[f.keyName] = items;
                            })))
                .toList())
      ]);
    }
    if (f.type == 'select') {
      final current = f.options.any((o) => o.$1 == '$value') ? '$value' : null;
      return DropdownButtonFormField<String>(
          key: ValueKey('${f.keyName}-$current-${f.options.length}'),
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: '${f.title}${f.optional ? ' (optional)' : ''}'),
          items: [
            if (f.optional)
              const DropdownMenuItem(value: '', child: Text('Not assigned')),
            ...f.options.map((o) => DropdownMenuItem(
                value: o.$1,
                child: Text(o.$2, overflow: TextOverflow.ellipsis)))
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                    values[f.keyName] = v;
                    if (f.keyName == 'blockId') {
                      values['roomId'] = '';
                      values['messId'] = '';
                    }
                    if (f.keyName == 'book') {
                      values['targetId'] = '';
                    }
                  }),
          validator: (v) => !f.optional && (v == null || v.isEmpty)
              ? 'Select ${f.title.toLowerCase()}'
              : null);
    }
    if (f.type == 'datetime' || f.type == 'date') {
      final parsed = DateTime.tryParse('$value');
      return FormField<String>(
          validator: (_) =>
              parsed == null ? 'Choose ${f.title.toLowerCase()}' : null,
          builder: (state) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton.icon(
                    onPressed: busy ? null : () => pickDate(f),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(parsed == null
                        ? f.title
                        : '${f.title}: ${f.type == 'date' ? DateFormat.yMMMd().format(parsed) : DateFormat.yMMMd().add_jm().format(parsed.toLocal())}')),
                if (state.hasError)
                  Text(state.errorText!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
              ]));
    }
    return TextFormField(
        key: ValueKey(f.keyName),
        initialValue: value?.toString() ?? '',
        enabled: !busy,
        decoration: InputDecoration(
            labelText: '${f.title}${f.optional ? ' (optional)' : ''}'),
        keyboardType: f.type == 'number'
            ? TextInputType.number
            : f.type == 'email'
                ? TextInputType.emailAddress
                : ['long', 'lines'].contains(f.type)
                    ? TextInputType.multiline
                    : TextInputType.text,
        maxLines: ['long', 'lines'].contains(f.type) ? 4 : 1,
        maxLength: ['long', 'lines'].contains(f.type) ? 10000 : 500,
        onChanged: (v) => values[f.keyName] = v,
        validator: (v) {
          if (!f.optional && (v == null || v.trim().isEmpty)) {
            return 'Enter ${f.title.toLowerCase()}';
          }
          if (f.type == 'number' && int.tryParse(v ?? '') == null) {
            return 'Enter a whole number';
          }
          return null;
        });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _key,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    for (final f in widget.fields(values))
                      Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: field(f)),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    FilledButton.icon(
                        onPressed: busy ? null : save,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: Text(busy ? 'Saving...' : 'Confirm & save')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

List<Field> withLookups(List<Field> fields, String resource,
    Map<String, dynamic> values, Map<String, dynamic> data) {
  final block = values['blockId'] ??
      values['studentBlockId'] ??
      rows(data, 'users')
          .where((u) => u['id'] == values['studentId'])
          .firstOrNull?['blockId'] ??
      '';
  return fields.map((f) {
    String? remote;
    switch (f.keyName) {
      case 'studentId':
        remote =
            '/options/students?book=${resource == 'discipline' ? 'DISCIPLINE' : 'OUTINGS'}';
      case 'userId':
        remote = '/options/staff';
      case 'roomId':
        remote = '/options/rooms?block=${Uri.encodeComponent('$block')}';
      case 'blockId':
        remote = '/options/blocks';
      case 'messId':
        remote =
            '/options/messes?block=${resource == 'users' ? Uri.encodeComponent('$block') : ''}';
      case 'targetId':
        remote =
            '/options/${values['book'] == 'MESS' ? 'messes' : values['book'] == 'CLOAKROOM' ? 'storageRooms' : 'blocks'}';
      case 'storageId':
        if (resource == 'cloakroom/request') {
          remote =
              '/options/storageRooms?block=${Uri.encodeComponent('$block')}';
        }
    }
    return remote == null
        ? f
        : Field(f.keyName, f.title,
            type: f.type,
            optional: f.optional,
            options: f.options,
            remote: remote);
  }).toList();
}
