import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'services/api.dart';
import 'forms.dart';
import 'remote_options.dart';

class DiningScreen extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  const DiningScreen({super.key, required this.api, required this.user});
  @override
  State<DiningScreen> createState() => _DiningState();
}

class _DiningState extends State<DiningScreen> {
  late String mess, tab;
  Map<String, dynamic> data = {};
  String? error;
  bool busy = false;
  int page = 0;
  int loadGeneration = 0;
  bool get student => widget.user['role'] == 'STUDENT';
  bool get caterer => widget.user['role'] == 'MESS_MANAGER';
  bool get manage =>
      ['ADMIN', 'DIRECTOR'].contains(widget.user['role']) ||
      widget.user['role'] == 'WARDEN' && has(widget.user, 'MESS', mess);
  @override
  void initState() {
    super.initState();
    mess = widget.user['messId'] ?? '';
    tab = caterer ? 'feedback' : 'menu';
    load();
  }

  Future<void> load() async {
    final generation = ++loadGeneration;
    if (mess.isEmpty) return;
    try {
      final path = switch (tab) {
        'menu' => '/dining/menus?mess=$mess',
        'sessions' => '/dining/sessions?mess=$mess&page=$page',
        'feedback' => '/dining/feedback?mess=$mess&page=$page',
        'performance' => '/dining/performance?mess=$mess',
        _ => '/records/polls?mess=$mess&page=$page'
      };
      final result = await widget.api.call(path);
      if (mounted && generation == loadGeneration) {
        setState(() {
          data = result is List ? {'items': result} : Map.from(result);
          error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == loadGeneration) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> mutate(String path, Map<String, dynamic> body) async {
    setState(() => busy = true);
    try {
      await widget.api.call(path, method: 'POST', body: body);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> form(String kind, [Map<String, dynamic>? row]) async {
    final r = row ?? {};
    final initial = <String, dynamic>{
      'messId': mess,
      'day': 'MON',
      'enabled': true,
      'kind': 'COMMENT',
      ...r
    };
    final ratingOptions =
        [1, 2, 3, 4, 5].map((n) => (n.toString(), '$n / 5')).toList();
    final items = List<Map<String, dynamic>>.from(r['items'] ?? []);
    final fields = kind == 'menu'
        ? [
            Field('day', 'Day',
                type: 'select',
                options:
                    choices(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])),
            for (final meal in ['breakfast', 'lunch', 'snacks', 'dinner'])
              Field(meal, label(meal), type: 'textarea')
          ]
        : kind == 'rate'
            ? [
                Field('rating', 'Caterer rating',
                    type: 'select', options: ratingOptions),
                for (final item in items)
                  Field(item['id'], item['name'],
                      type: 'select', options: ratingOptions),
                Field('kind', 'Type',
                    type: 'select', options: choices(['COMMENT', 'COMPLAINT'])),
                const Field(
                    'comment', 'Comment (do not include identifying details)',
                    type: 'textarea', optional: true)
              ]
            : [
                const Field('title', 'Title'),
                if (kind == 'session')
                  const Field('opensAt', 'Opens at', type: 'datetime'),
                const Field('closesAt', 'Closes at', type: 'datetime'),
                Field(
                    kind == 'session' ? 'items' : 'options',
                    kind == 'session'
                        ? 'Food items, one per line'
                        : 'Options, one per line',
                    type: 'lines')
              ];
    final path = switch (kind) {
      'menu' => '/menus',
      'session' => '/dining/sessions',
      'rate' => '/dining/sessions/${r['id']}/submit',
      _ => '/polls'
    };
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title: kind == 'rate' ? 'Anonymous feedback' : label(kind),
                path: path,
                api: widget.api,
                initial: initial,
                fields: (_) => fields,
                transform: kind == 'rate'
                    ? (b) => {
                          'rating': int.parse(b['rating']),
                          'kind': b['kind'],
                          'comment': b['comment'] ?? '',
                          'ratings': {
                            for (final item in items)
                              item['id']: int.parse(b[item['id']])
                          }
                        }
                    : null)));
    if (saved == true) await load();
  }

  Future<void> upload() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'Menu', extensions: ['csv', 'json'])
      ]);
      if (file == null) return;
      if (await file.length() > 100000) {
        throw Exception('File must be under 100 KB');
      }
      final text = await file.readAsString();
      await mutate('/dining/menus/upload', {
        'messId': mess,
        if (file.name.toLowerCase().endsWith('.csv'))
          'csv': text
        else
          'menus': jsonDecode(text)
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = caterer
        ? ['feedback']
        : student
            ? ['menu', 'sessions', 'polls']
            : [
                'menu',
                'sessions',
                'feedback',
                if (manage) ...['performance', 'polls']
              ];
    return RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!student && !caterer)
            RemoteOption(
                api: widget.api,
                path: '/options/messes',
                title: 'Caterer',
                value: mess,
                onSelected: (o) {
                  setState(() {
                    mess = o?['value'] ?? '';
                    data = {};
                    page = 0;
                  });
                  load();
                }),
          if (mess.isEmpty)
            const Text('No caterer assigned.')
          else ...[
            DropdownButton<String>(
                value: tab,
                items: tabs
                    .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t == 'sessions' ? 'Rate food' : label(t))))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    tab = v!;
                    data = {};
                    page = 0;
                  });
                  load();
                }),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            if (tab == 'menu') ...[
              if (manage)
                Wrap(spacing: 8, children: [
                  OutlinedButton(
                      onPressed: () => form('menu'),
                      child: const Text('Edit menu')),
                  OutlinedButton(
                      onPressed: busy ? null : upload,
                      child: const Text('Upload menu'))
                ]),
              for (final m in rows(data, 'items'))
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['day'],
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              for (final meal in [
                                'breakfast',
                                'lunch',
                                'snacks',
                                'dinner'
                              ])
                                Text('${label(meal)}: ${m[meal]}'),
                              if (manage)
                                TextButton(
                                    onPressed: () => form('menu', m),
                                    child: const Text('Edit'))
                            ])))
            ],
            if (tab == 'sessions') ...[
              if (manage) ...[
                SwitchListTile(
                    title: const Text('Accept feedback'),
                    value: data['enabled'] == true,
                    onChanged: busy
                        ? null
                        : (v) => mutate(
                            '/dining/enabled', {'messId': mess, 'enabled': v})),
                OutlinedButton(
                    onPressed: () => form('session'),
                    child: const Text('New session'))
              ],
              for (final s in rows(data, 'sessions'))
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['title']),
                              Text('${s['opensAt']} – ${s['closesAt']}'),
                              Text((s['items'] as List)
                                  .map((i) => i['name'])
                                  .join(', ')),
                              if (student)
                                FilledButton(
                                    onPressed: s['submitted'] == true ||
                                            data['enabled'] != true ||
                                            s['enabled'] != true ||
                                            DateTime.now().isBefore(
                                                DateTime.parse(s['opensAt'])) ||
                                            !DateTime.now().isBefore(
                                                DateTime.parse(s['closesAt']))
                                        ? null
                                        : () => form('rate', s),
                                    child: Text(s['submitted'] == true
                                        ? 'Submitted'
                                        : 'Rate this session')),
                              if (manage)
                                SwitchListTile(
                                    title: const Text('Session open'),
                                    value: s['enabled'] == true,
                                    onChanged: busy
                                        ? null
                                        : (v) => mutate(
                                            '/dining/sessions/${s['id']}/state',
                                            {'enabled': v}))
                            ])))
            ],
            if (tab == 'feedback')
              for (final f in rows(data, 'items'))
                Card(
                    child: ListTile(
                        title: Text('${f['sessionTitle']} · ${f['rating']}/5'),
                        subtitle: Text(
                            '${label(f['kind'])}: ${f['comment']}\n${(f['items'] as List).map((i) => '${i['name']}: ${i['rating']}/5').join(', ')}'))),
            if (tab == 'performance' && data['caterer'] != null) ...[
              Text(
                  '${data['caterer']['responses']} responses · Caterer ${data['caterer']['rating']}/5'),
              for (final i in rows(data, 'items'))
                ListTile(
                    title: Text(i['name']),
                    subtitle:
                        Text('${i['responses']} ratings · ${i['rating']}/5'))
            ],
            if (tab == 'polls') ...[
              if (manage)
                OutlinedButton(
                    onPressed: () => form('poll'),
                    child: const Text('New poll')),
              for (final p in rows(data, 'items'))
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          Text(p['title']),
                          for (final o in p['options'])
                            ListTile(
                                title: Text('${o['label']} · ${o['votes']}'),
                                trailing: student
                                    ? TextButton(
                                        onPressed: busy ||
                                                p['myVote'] != '' ||
                                                p['enabled'] != true ||
                                                !DateTime.now().isBefore(
                                                    DateTime.parse(
                                                        p['closesAt']))
                                            ? null
                                            : () => mutate(
                                                '/polls/${p['id']}/action',
                                                {'optionId': o['id']}),
                                        child: const Text('Vote'))
                                    : null),
                          if (manage)
                            SwitchListTile(
                                title: const Text('Open'),
                                value: p['enabled'] == true,
                                onChanged: busy
                                    ? null
                                    : (v) => mutate('/polls/${p['id']}/state',
                                        {'enabled': v}))
                        ])))
            ],
            if (['feedback', 'polls', 'sessions'].contains(tab))
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(
                    onPressed: page == 0
                        ? null
                        : () {
                            setState(() => page--);
                            load();
                          },
                    child: const Text('Previous')),
                Text('Page ${page + 1}'),
                TextButton(
                    onPressed: (page + 1) * 25 >= (data['total'] ?? 0)
                        ? null
                        : () {
                            setState(() => page++);
                            load();
                          },
                    child: const Text('Next'))
              ])
          ]
        ]));
  }
}
