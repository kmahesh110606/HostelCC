import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'services/api.dart';
import 'forms.dart';

class OperationsScreen extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final String section;
  const OperationsScreen(
      {super.key,
      required this.api,
      required this.user,
      required this.section});
  @override
  State<OperationsScreen> createState() => _OperationsState();
}

class _OperationsState extends State<OperationsScreen> {
  Map<String, dynamic> data = {};
  String? error;
  String resource = 'outings', query = '';
  int page = 0;
  bool busy = false;
  Set<String> columns = {};
  List<Map<String, dynamic>> report = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(OperationsScreen old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section) {
      page = 0;
      data = {};
      report = [];
      load();
    }
  }

  Future<void> load() async {
    try {
      final result = await widget.api.call(widget.section == 'books'
          ? '/campus/books'
          : '/records/${widget.section == 'gate' ? 'gate' : resource}?page=$page&q=${Uri.encodeComponent(query)}');
      if (mounted) {
        setState(() {
          data = result is List ? {'items': result} : Map.from(result);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> form([Map<String, dynamic>? row]) async {
    final gate = widget.section == 'gate';
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RecordForm(
                title: gate ? 'Entry / exit' : 'Duty book',
                path: gate
                    ? '/campus/gate'
                    : '/campus/books${row == null ? '' : '/${row['id']}'}',
                method: row == null ? 'POST' : 'PUT',
                api: widget.api,
                initial: {
                  'baseBook': 'HOSTEL',
                  'active': true,
                  'direction': 'EXIT',
                  ...?row
                },
                fields: (_) => gate
                    ? [
                        const Field('studentId', 'Student',
                            remote: '/options/students?book=OUTINGS'),
                        Field('direction', 'Direction',
                            type: 'select',
                            options: choices(['ENTRY', 'EXIT'])),
                        const Field('note', 'Note',
                            type: 'textarea', optional: true)
                      ]
                    : [
                        const Field('name', 'Name'),
                        Field('baseBook', 'Permissions',
                            type: 'select',
                            options: choices([
                              'HOSTEL',
                              'MESS',
                              'OUTINGS',
                              'DISCIPLINE',
                              'MAINTENANCE',
                              'CLOAKROOM'
                            ])),
                        const Field('active', 'Active', type: 'bool')
                      ])));
    if (saved == true) await load();
  }

  Future<void> buildReport() async {
    setState(() => busy = true);
    try {
      final result = <Map<String, dynamic>>[];
      var p = 0;
      Map<String, dynamic> batch;
      do {
        batch = Map.from(await widget.api.call(
            '/records/$resource?page=${p++}&size=100&q=${Uri.encodeComponent(query)}'));
        result.addAll(rows(batch, 'items'));
        if (result.length > 20000) {
          throw Exception('Narrow the search to 20,000 records or fewer');
        }
      } while (p * 100 < batch['total']);
      if (mounted) setState(() => report = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(bool pdf) async {
    try {
      Uint8List bytes;
      if (pdf) {
        final document = pw.Document();
        document.addPage(pw.MultiPage(
            maxPages: 1000,
            build: (_) => [
                  pw.Text(label(resource)),
                  pw.TableHelper.fromTextArray(
                      headers: columns.map(label).toList(),
                      data: report
                          .map((r) =>
                              columns.map((k) => '${r[k] ?? ''}').toList())
                          .toList())
                ]));
        bytes = await document.save();
      } else {
        String cell(dynamic value) {
          var text = '$value';
          if (RegExp(r'^[=+@-]').hasMatch(text)) text = "'$text";
          return '"${text.replaceAll('"', '""')}"';
        }

        bytes = Uint8List.fromList(utf8.encode('\uFEFF${[
          columns.toList(),
          ...report.map((r) => columns.map((k) => r[k] ?? '').toList())
        ].map((r) => r.map(cell).join(',')).join('\r\n')}'));
      }
      await Share.shareXFiles([
        XFile.fromData(bytes,
            mimeType: pdf ? 'application/pdf' : 'text/csv',
            name: '$resource.${pdf ? 'pdf' : 'csv'}')
      ], fileNameOverrides: [
        '$resource.${pdf ? 'pdf' : 'csv'}'
      ]);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = rows(data, 'items');
    final available = records.isEmpty
        ? <String>[]
        : records.first.keys
            .where((k) => k != 'id' && !k.endsWith('Id') && k != 'qrToken')
            .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (widget.section == 'reports') ...[
        DropdownButton<String>(
            value: resource,
            isExpanded: true,
            items: [
              'users',
              'rooms',
              'outings',
              'gate',
              'discipline',
              'maintenance',
              'cloakroom',
              'feedback',
              'audit'
            ]
                .map((k) => DropdownMenuItem(value: k, child: Text(label(k))))
                .toList(),
            onChanged: (v) {
              setState(() {
                resource = v!;
                columns = {};
                report = [];
                page = 0;
              });
              load();
            }),
        TextField(
            decoration: const InputDecoration(labelText: 'Search'),
            onChanged: (v) => query = v,
            onSubmitted: (_) => load()),
        for (final k in available)
          CheckboxListTile(
              title: Text(label(k)),
              value: columns.contains(k),
              onChanged: (v) => setState(() {
                    v == true ? columns.add(k) : columns.remove(k);
                  })),
        FilledButton(
            onPressed: busy || columns.isEmpty ? null : buildReport,
            child: const Text('Build report')),
        Text('${report.length} records'),
        Wrap(spacing: 8, children: [
          OutlinedButton(
              onPressed: report.isEmpty ? null : () => export(false),
              child: const Text('CSV / Excel')),
          OutlinedButton(
              onPressed: report.isEmpty ? null : () => export(true),
              child: const Text('PDF'))
        ])
      ] else ...[
        if (widget.section == 'books' || has(widget.user, 'OUTINGS'))
          OutlinedButton(
              onPressed: () => form(), child: const Text('Add record')),
        for (final r in records)
          Card(
              child: ListTile(
                  title: Text(widget.section == 'books'
                      ? r['name']
                      : '${r['studentName']} · ${label(r['direction'])}'),
                  subtitle: Text(widget.section == 'books'
                      ? '${label(r['baseBook'])} · ${r['active'] == true ? 'Active' : 'Inactive'}'
                      : '${r['recordedAt']}\n${r['note']}'),
                  onTap: widget.section == 'books' ? () => form(r) : null)),
        if (widget.section == 'gate')
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
      ]
    ]);
  }
}
