import 'package:flutter/material.dart';
import 'services/api.dart';
import 'forms.dart';
import 'remote_options.dart';

class StudentHistoryScreen extends StatefulWidget {
  final Api api;
  final String id;
  const StudentHistoryScreen({super.key, required this.api, required this.id});
  @override
  State<StudentHistoryScreen> createState() => _StudentHistoryState();
}

class _StudentHistoryState extends State<StudentHistoryScreen> {
  Map<String, dynamic> student = {}, data = {};
  String kind = 'outings';
  String? error;
  int page = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final person = await widget.api.call('/campus/students/${widget.id}');
      final history = await widget.api
          .call('/campus/students/${widget.id}/$kind?page=$page');
      if (mounted) {
        setState(() {
          student = Map.from(person);
          data = Map.from(history);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(student['name'] ?? 'Student')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null) Text(error!),
        Text(
            '${student['rollNo'] ?? ''} · ${student['blockName'] ?? ''} · ${student['roomNumber'] ?? ''}'),
        Text('${student['email'] ?? ''}\n${student['phone'] ?? ''}'),
        Text('Caterer: ${student['messName'] ?? 'Unassigned'}'),
        DropdownButton<String>(
            value: kind,
            items: ['outings', 'discipline', 'gate', 'cloakroom']
                .map((k) => DropdownMenuItem(
                    value: k,
                    child: Text(k == 'gate' ? 'Entry / exit' : label(k))))
                .toList(),
            onChanged: (v) {
              setState(() {
                kind = v!;
                page = 0;
              });
              load();
            }),
        for (final r in rows(data, 'items'))
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in r.entries)
                          if (e.key != 'id' &&
                              !e.key.endsWith('Id') &&
                              e.value != null &&
                              e.value != '')
                            Text('${label(e.key)}: ${e.value}')
                      ]))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(
              onPressed: page == 0
                  ? null
                  : () {
                      page--;
                      load();
                    },
              child: const Text('Previous')),
          Text('Page ${page + 1}'),
          TextButton(
              onPressed: (page + 1) * 25 >= (data['total'] ?? 0)
                  ? null
                  : () {
                      page++;
                      load();
                    },
              child: const Text('Next'))
        ])
      ]));
}

class CampusScreen extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  const CampusScreen({super.key, required this.api, required this.user});
  @override
  State<CampusScreen> createState() => _CampusState();
}

class _CampusState extends State<CampusScreen> {
  String block = '';
  List<Map<String, dynamic>> floors = [];
  Map<String, dynamic>? floor;
  String? error;
  bool editing = false, busy = false;
  bool get admin => widget.user['role'] == 'ADMIN';
  Future<void> load() async {
    if (block.isEmpty) return;
    try {
      final result = await widget.api.call('/campus/floors?block=$block');
      if (mounted) {
        setState(() => floors = List<Map<String, dynamic>>.from(result));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> choose(String id) async {
    try {
      final result = await widget.api.call('/campus/floors/$id');
      if (mounted) {
        setState(() {
          floor = Map.from(result);
          editing = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> floorForm() async {
    final existing = floor;
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title: existing == null ? 'Add floor' : 'Floor settings',
                path:
                    '/campus/floors${existing == null ? '' : '/${existing['id']}'}',
                method: existing == null ? 'POST' : 'PUT',
                api: widget.api,
                initial: {
                  'blockId': block,
                  'width': 1000,
                  'height': 650,
                  'sortOrder': 0,
                  'elements': [],
                  ...?existing
                },
                fields: (_) => [
                      const Field('name', 'Floor name'),
                      const Field('width', 'Width', type: 'number'),
                      const Field('height', 'Height', type: 'number'),
                      const Field('sortOrder', 'Order', type: 'number')
                    ])));
    if (saved == true) {
      await load();
      if (existing != null) await choose(existing['id']);
    }
  }

  Future<void> elementForm([int? index]) async {
    final f = floor!;
    final elements = List<Map<String, dynamic>>.from(f['elements']);
    final initial = index == null
        ? <String, dynamic>{
            'kind': 'ROOM',
            'x': 10,
            'y': 10,
            'width': 100,
            'height': 80,
            'label': ''
          }
        : elements[index];
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title: 'Layout element',
                path: '/campus/floors/${f['id']}',
                method: 'PUT',
                api: widget.api,
                initial: initial,
                fields: (v) => [
                      Field('kind', 'Type',
                          type: 'select',
                          options: choices([
                            'ROOM',
                            'CORRIDOR',
                            'STAIRS',
                            'LIFT',
                            'WALL',
                            'LABEL'
                          ])),
                      if (v['kind'] == 'ROOM')
                        Field('roomId', 'Room',
                            remote: '/options/rooms?block=$block')
                      else
                        const Field('label', 'Label', optional: true),
                      for (final k in ['x', 'y', 'width', 'height'])
                        Field(k, label(k), type: 'number')
                    ],
                transform: (value) {
                  if (value['kind'] != 'ROOM') value['roomId'] = '';
                  if (index == null) {
                    elements.add(value);
                  } else {
                    elements[index] = value;
                  }
                  return {...f, 'elements': elements};
                })));
    if (saved == true) {
      await choose(f['id']);
      if (mounted) setState(() => editing = true);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.api
          .call('/campus/floors/${floor!['id']}', method: 'PUT', body: floor);
      await choose(floor!['id']);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> occupants(Map<String, dynamic> element) async {
    if (element['roomId'] == null) return;
    try {
      final result = await widget.api
          .call('/campus/rooms/${element['roomId']}/students') as List;
      if (!mounted) return;
      await showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(title: Text('Room ${element['roomNumber'] ?? ''}')),
                if (result.isEmpty)
                  const ListTile(title: Text('No assigned students')),
                for (final s in result)
                  ListTile(
                      title: Text(s['name']),
                      subtitle: Text(s['rollNo']),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(this.context).push(MaterialPageRoute(
                            builder: (_) => StudentHistoryScreen(
                                api: widget.api, id: s['id'])));
                      })
              ])));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = floor;
    return ListView(padding: const EdgeInsets.all(16), children: [
      RemoteOption(
          api: widget.api,
          path: '/options/blocks',
          title: 'Block',
          value: block,
          onSelected: (o) {
            setState(() {
              block = o?['value'] ?? '';
              floor = null;
              editing = false;
            });
            load();
          }),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      DropdownButton<String>(
          value: f?['id'],
          hint: const Text('Choose floor'),
          isExpanded: true,
          items: floors
              .map((e) => DropdownMenuItem<String>(
                  value: e['id'], child: Text(e['name'])))
              .toList(),
          onChanged: (id) {
            if (id != null) choose(id);
          }),
      if (admin && block.isNotEmpty)
        Wrap(spacing: 8, children: [
          OutlinedButton(
              onPressed: () {
                setState(() => floor = null);
                floorForm();
              },
              child: const Text('Add floor')),
          if (f != null) ...[
            OutlinedButton(
                onPressed: floorForm, child: const Text('Floor settings')),
            OutlinedButton(
                onPressed: () => setState(() => editing = !editing),
                child: Text(editing ? 'View rooms' : 'Edit layout'))
          ]
        ]),
      if (f != null) ...[
        if (editing)
          Wrap(spacing: 8, children: [
            OutlinedButton(
                onPressed: () => elementForm(),
                child: const Text('Add element')),
            FilledButton(
                onPressed: busy ? null : save,
                child: const Text('Save positions'))
          ]),
        SizedBox(
            height: 500,
            child: InteractiveViewer(
                constrained: false,
                minScale: 0.2,
                maxScale: 3,
                child: SizedBox(
                    width: (f['width'] as num).toDouble(),
                    height: (f['height'] as num).toDouble(),
                    child: Stack(children: [
                      for (var i = 0; i < (f['elements'] as List).length; i++)
                        elementWidget(
                            Map<String, dynamic>.from(f['elements'][i]), i)
                    ])))),
        if (editing)
          for (var i = 0; i < (f['elements'] as List).length; i++)
            ListTile(
                title: Text(
                    '${f['elements'][i]['roomNumber'] ?? f['elements'][i]['label'] ?? ''} ${label(f['elements'][i]['kind'])}'),
                onTap: () => elementForm(i),
                trailing: IconButton(
                    tooltip: 'Remove element',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(
                        () => (floor!['elements'] as List).removeAt(i))))
      ]
    ]);
  }

  Widget elementWidget(Map<String, dynamic> e, int index) => Positioned(
      left: (e['x'] as num).toDouble(),
      top: (e['y'] as num).toDouble(),
      width: (e['width'] as num).toDouble(),
      height: (e['height'] as num).toDouble(),
      child: GestureDetector(
          onTap: () => editing ? elementForm(index) : occupants(e),
          onPanUpdate: editing
              ? (details) {
                  setState(() {
                    final item = floor!['elements'][index];
                    item['x'] = (item['x'] + details.delta.dx)
                        .round()
                        .clamp(0, floor!['width'] - item['width']);
                    item['y'] = (item['y'] + details.delta.dy)
                        .round()
                        .clamp(0, floor!['height'] - item['height']);
                  });
                }
              : null,
          child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: e['kind'] == 'ROOM'
                      ? const Color(0xffeef4ef)
                      : const Color(0xffe5e7e6),
                  border: Border.all(color: Colors.grey)),
              child: Text(
                  '${e['roomNumber'] ?? e['label'] ?? label(e['kind'])}${e['kind'] == 'ROOM' ? '\n${e['occupied'] ?? 0}/${e['capacity'] ?? 0}' : ''}',
                  textAlign: TextAlign.center))));
}
