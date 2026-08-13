import 'package:flutter/material.dart';

import 'models.dart';
import 'split_utils.dart';
import 'supabase_service.dart';

const _teal = Color(0xFF0E7C86);
const _coral = Color(0xFFE8663D);

Color colorOf(Person? p) {
  final hex = p?.color;
  if (hex == null) return const Color(0xFF8A94A6);
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF8A94A6) : Color(v);
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  return parts.take(2).map((w) => w[0].toUpperCase()).join();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = UrlaubskasseService();

  List<Trip> _trips = [];
  Trip? _trip;
  List<Person> _persons = [];
  List<Expense> _expenses = [];
  List<BudgetPeriod> _periods = [];

  bool _loading = true;
  String? _error;
  int _tab = 0;

  Person? personById(String id) {
    for (final p in _persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await _service.fetchTrips();
      _trips = trips;
      _trip = trips.isNotEmpty ? trips.first : null;
      if (_trip != null) {
        await _loadTripData();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadTripData() async {
    if (_trip == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final persons = await _service.fetchPersons(_trip!.id);
      final expenses = await _service.fetchExpenses(_trip!.id);
      final periods = await _service.fetchBudgetPeriods(_trip!.id);
      setState(() {
        _persons = persons;
        _expenses = expenses;
        _periods = periods;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openExpenseForm({Expense? existing, String? defaultDate}) async {
    if (_trip == null || _persons.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExpenseSheet(
        persons: _persons,
        existing: existing,
        defaultDate: defaultDate ?? fmtDate(DateTime.now()),
        onSubmit: (data, id) async {
          if (id == null) {
            await _service.addExpense(
              tripId: _trip!.id,
              spentBy: data.spentBy,
              amount: data.amount,
              description: data.description,
              expenseDate: data.expenseDate,
              splitMethod: data.splitMethod,
              participants: data.participants,
            );
          } else {
            await _service.updateExpense(
              id: id,
              spentBy: data.spentBy,
              amount: data.amount,
              description: data.description,
              expenseDate: data.expenseDate,
              splitMethod: data.splitMethod,
              participants: data.participants,
            );
          }
        },
      ),
    );
    if (ok == true) await _loadTripData();
  }

  Future<void> _openExpenseActions(Expense e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Bearbeiten'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _coral),
              title: const Text('Löschen',
                  style: TextStyle(color: _coral)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _openExpenseForm(existing: e);
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Ausgabe löschen?'),
          content: Text(e.description.isEmpty ? 'Diese Ausgabe' : e.description),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Löschen')),
          ],
        ),
      );
      if (confirm == true) {
        await _service.deleteExpense(e.id);
        await _loadTripData();
      }
    }
  }

  Future<void> _openBudgetSheet() async {
    if (_trip == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BudgetSheet(
        periods: _periods,
        onAdd: (start, end, amount) => _service.addBudgetPeriod(
          tripId: _trip!.id,
          startDate: start,
          endDate: end,
          dailyAmount: amount,
        ),
        onDelete: (id) => _service.deleteBudgetPeriod(id),
      ),
    );
    if (changed == true) await _loadTripData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _trips.length > 1
            ? DropdownButton<Trip>(
                value: _trip,
                underline: const SizedBox.shrink(),
                items: _trips
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (t) {
                  if (t == null) return;
                  setState(() => _trip = t);
                  _loadTripData();
                },
              )
            : Text(_trip?.name ?? 'Urlaubskasse'),
        actions: [
          if (_trip != null)
            TextButton.icon(
              onPressed: _openBudgetSheet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Budget'),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: (!_loading && _tab == 0 && _persons.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () => _openExpenseForm(),
              icon: const Icon(Icons.add),
              label: const Text('Ausgabe'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Budget'),
          NavigationDestination(
              icon: Icon(Icons.balance_outlined),
              selectedIcon: Icon(Icons.balance),
              label: 'Abrechnung'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(message: _error!, onRetry: _loadTrips);
    if (_trip == null) return const Center(child: Text('Keine Reise gefunden.'));
    return RefreshIndicator(
      onRefresh: _loadTripData,
      child: _tab == 0 ? _budgetView() : _settlementView(),
    );
  }

  // -------------------- Budget / Tagesansicht --------------------
  Widget _budgetView() {
    final days = tripDays(_periods, _expenses);
    final tBudget = totalBudget(_periods);
    final tSpent = totalSpent(_expenses);
    final tRest = tBudget - tSpent;
    final byDay = <String, List<Expense>>{};
    for (final e in _expenses) {
      byDay.putIfAbsent(e.expenseDate ?? '', () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        // Gesamtrechnung oben
        Card(
          color: tRest >= 0 ? const Color(0xFFEAF5F5) : const Color(0xFFFDECE6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Gesamt', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _totalCell('Budget', tBudget, Colors.black87),
                    _totalCell('Ausgaben', tSpent, Colors.black87),
                    _totalCell('Rest', tRest, tRest >= 0 ? _teal : _coral),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (days.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
                child: Text(
              'Noch kein Budget-Zeitraum und keine Ausgaben.\n'
              'Tippe oben auf „Budget", um einen Zeitraum anzulegen.',
              textAlign: TextAlign.center,
            )),
          ),
        ...days.map((day) => _dayCard(day, byDay[day] ?? [])),
      ],
    );
  }

  Widget _totalCell(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 2),
        Text(euro(value),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _dayCard(String day, List<Expense> dayExpenses) {
    final budget = dailyBudgetForDate(_periods, day);
    final spent = dayExpenses.fold(0.0, (a, e) => a + e.amount);
    final rest = budget - spent;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LINKS 25% : Budget des Tages
            Expanded(
              flex: 25,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: rest >= 0
                      ? const Color(0xFFF1F7F7)
                      : const Color(0xFFFBEEE9),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${weekdayLabel(day)} ${dateLabel(day)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    _kv('Budget', budget, Colors.black87),
                    _kv('Aus', spent, Colors.black54),
                    const Divider(height: 12),
                    _kv('Rest', rest, rest >= 0 ? _teal : _coral, bold: true),
                  ],
                ),
              ),
            ),
            // RECHTS 75% : Ausgaben des Tages
            Expanded(
              flex: 75,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: dayExpenses.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('keine Ausgaben',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : Column(
                        children: dayExpenses.map((e) {
                          final payer = personById(e.spentBy);
                          return InkWell(
                            onTap: () => _openExpenseActions(e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  _Avatar(person: payer, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.description.isEmpty
                                              ? 'Ausgabe'
                                              : e.description,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        if (e.participants.isNotEmpty)
                                          Text(
                                            e.participants
                                                .map((p) =>
                                                    personById(p.personId)
                                                        ?.name ??
                                                    '?')
                                                .join(', '),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(euro(e.amount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const Icon(Icons.chevron_right,
                                      size: 18, color: Colors.grey),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, double v, Color c, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(euro(v),
              style: TextStyle(
                  fontSize: 12.5,
                  color: c,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  // -------------------- Abrechnung (Kassen) --------------------
  Widget _settlementView() {
    final kassen = computeKassen(_persons, _expenses);
    final transfers = computeKasseSettlement(_persons, _expenses);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('Stand pro Kasse',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: Column(
            children: kassen.map((k) {
              final pos = k.net >= 0;
              final grouped = k.members.length > 1;
              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KasseDetailScreen(
                        kasse: k, persons: _persons, expenses: _expenses),
                  ),
                ),
                leading: _Avatar(person: k.members.first, size: 34),
                title: Text(k.label),
                subtitle: grouped
                    ? Text(k.members.map((m) => m.name).join(' + '),
                        style: const TextStyle(fontSize: 12))
                    : null,
                trailing: Text(
                  '${pos ? '+' : ''}${euro(k.net)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: pos ? _teal : _coral),
                ),
              );
            }).toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text('Ausgleich',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: transfers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Alles ausgeglichen ✓')),
                )
              : Column(
                  children: transfers.map((t) {
                    return ListTile(
                      title: Row(
                        children: [
                          Flexible(child: Text(t.from.label)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 16),
                          ),
                          Flexible(child: Text(t.to.label)),
                        ],
                      ),
                      trailing: Text(euro(t.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final Person? person;
  final double size;
  const _Avatar({required this.person, required this.size});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colorOf(person),
      child: Text(initials(person?.name ?? '?'),
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Konnte Daten nicht laden.',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Erneut')),
          ],
        ),
      ),
    );
  }
}

// ============================ Ausgabe-Formular ============================

class NewExpense {
  final String spentBy;
  final double amount;
  final String description;
  final String expenseDate;
  final String splitMethod;
  final List<Map<String, dynamic>> participants;
  NewExpense({
    required this.spentBy,
    required this.amount,
    required this.description,
    required this.expenseDate,
    required this.splitMethod,
    required this.participants,
  });
}

class ExpenseSheet extends StatefulWidget {
  final List<Person> persons;
  final Expense? existing;
  final String defaultDate;
  final Future<void> Function(NewExpense data, String? existingId) onSubmit;
  const ExpenseSheet({
    super.key,
    required this.persons,
    required this.defaultDate,
    required this.onSubmit,
    this.existing,
  });

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final TextEditingController _desc;
  late final TextEditingController _amount;
  final Map<String, TextEditingController> _shares = {};

  Person? _payer;
  late DateTime _date;
  String _method = 'equal';
  final Set<String> _selected = {};
  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _desc = TextEditingController(text: e?.description ?? '');
    _amount = TextEditingController(
        text: e != null ? e.amount.toStringAsFixed(2).replaceAll('.', ',') : '');
    _date = DateTime.tryParse(e?.expenseDate ?? widget.defaultDate) ??
        DateTime.now();
    if (e != null) {
      for (final p in widget.persons) {
        if (p.id == e.spentBy) _payer = p;
      }
      _selected.addAll(e.participants.map((p) => p.personId));
      final m = (e.splitMethod ?? '').toLowerCase();
      if (m.contains('exact') || m.contains('amount') || m.contains('betrag')) {
        _method = 'exact';
      } else if (e.participants.any((p) => p.share != null && p.share != 1)) {
        _method = 'shares';
      } else {
        _method = 'equal';
      }
      for (final p in e.participants) {
        if (p.share != null) {
          _shares[p.personId] = TextEditingController(
              text: p.share!.toStringAsFixed(2).replaceAll('.', ','));
        }
      }
    }
    _payer ??= widget.persons.isNotEmpty ? widget.persons.first : null;
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _shares.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _shareCtrl(String id) =>
      _shares.putIfAbsent(id, () => TextEditingController(text: '1'));

  String _fmt(DateTime d) => fmtDate(d);

  Future<void> _save() async {
    final desc = _desc.text.trim();
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (desc.isEmpty || amount <= 0) {
      setState(() => _msg = 'Bitte Zweck und gültigen Betrag angeben.');
      return;
    }
    if (_payer == null || _selected.isEmpty) {
      setState(() => _msg = 'Bitte Zahler und Beteiligte wählen.');
      return;
    }
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final participants = _selected.map((id) {
        double? share;
        if (_method != 'equal') {
          share =
              double.tryParse(_shareCtrl(id).text.trim().replaceAll(',', '.'));
        }
        return {'person_id': id, 'share': share};
      }).toList();

      await widget.onSubmit(
        NewExpense(
          spentBy: _payer!.id,
          amount: amount,
          description: desc,
          expenseDate: _fmt(_date),
          splitMethod: _method,
          participants: participants,
        ),
        widget.existing?.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _msg = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'Ausgabe bearbeiten' : 'Neue Ausgabe',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Wofür?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Betrag (€)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(dateLabel(_fmt(_date))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Person>(
              value: _payer,
              decoration: const InputDecoration(
                  labelText: 'Bezahlt von', border: OutlineInputBorder()),
              items: widget.persons
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (p) => setState(() => _payer = p),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Beteiligt',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(widget.persons.map((p) => p.id));
                  }),
                  child: const Text('alle'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.persons.map((p) {
                final sel = _selected.contains(p.id);
                return FilterChip(
                  avatar: _Avatar(person: p, size: 18),
                  label: Text(p.name),
                  selected: sel,
                  onSelected: (v) => setState(() {
                    v ? _selected.add(p.id) : _selected.remove(p.id);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(
                  labelText: 'Aufteilung', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'equal', child: Text('gleichmäßig teilen')),
                DropdownMenuItem(
                    value: 'shares', child: Text('nach Anteilen (Gewichte)')),
                DropdownMenuItem(value: 'exact', child: Text('feste Beträge')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'equal'),
            ),
            if (_method != 'equal' && _selected.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._selected.map((id) {
                final person = widget.persons.firstWhere((p) => p.id == id);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(person.name)),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _shareCtrl(id),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixText: _method == 'exact' ? '€' : 'x',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(_msg!, style: const TextStyle(color: Color(0xFFB23A16))),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(_saving
                      ? 'Speichere…'
                      : (editing ? 'Änderungen speichern' : 'Ausgabe speichern')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ Budget-Zeitraeume ============================

class BudgetSheet extends StatefulWidget {
  final List<BudgetPeriod> periods;
  final Future<void> Function(String start, String end, double amount) onAdd;
  final Future<void> Function(String id) onDelete;
  const BudgetSheet({
    super.key,
    required this.periods,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<BudgetSheet> {
  final _amount = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
          if (_end.isBefore(_start)) _end = _start;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _add() async {
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (amount <= 0) {
      setState(() => _msg = 'Bitte ein gültiges Tagesbudget eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await widget.onAdd(fmtDate(_start), fmtDate(_end), amount);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'Fehler: $e';
      });
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _busy = true);
    try {
      await widget.onDelete(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'Fehler: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Budget-Zeiträume',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.periods.isEmpty)
              const Text('Noch kein Budget-Zeitraum definiert.',
                  style: TextStyle(color: Colors.grey))
            else
              ...widget.periods.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${dateLabel(p.startDate)} – ${dateLabel(p.endDate)}'),
                    subtitle: Text('${euro(p.dailyAmount)} / Tag'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: _coral),
                      onPressed: _busy ? null : () => _delete(p.id),
                    ),
                  )),
            const Divider(height: 24),
            const Text('Neuen Zeitraum anlegen',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text('Von: ${dateLabel(fmtDate(_start))}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text('Bis: ${dateLabel(fmtDate(_end))}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tagesbudget (€)',
                border: OutlineInputBorder(),
                helperText: 'Für einen einzelnen Tag: Von = Bis wählen.',
              ),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Text(_msg!, style: const TextStyle(color: Color(0xFFB23A16))),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _add,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Zeitraum hinzufügen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ Kassen-Detail ============================

class KasseDetailScreen extends StatelessWidget {
  final KasseBalance kasse;
  final List<Person> persons;
  final List<Expense> expenses;
  const KasseDetailScreen({
    super.key,
    required this.kasse,
    required this.persons,
    required this.expenses,
  });

  Person? _p(String id) {
    for (final p in persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final memberIds = kasse.members.map((m) => m.id).toSet();

    final rows = <Widget>[];
    var totalPaid = 0.0;
    var totalOwed = 0.0;

    for (final e in expenses) {
      final owedMap = portionsFor(e);
      var owed = 0.0;
      for (final id in memberIds) {
        owed += owedMap[id] ?? 0;
      }
      final paid = memberIds.contains(e.spentBy) ? e.amount : 0.0;
      if (paid == 0 && owed == 0) continue;

      totalPaid += paid;
      totalOwed += owed;

      final payer = _p(e.spentBy);
      rows.add(
        ListTile(
          leading: _Avatar(person: payer, size: 30),
          title: Text(e.description.isEmpty ? 'Ausgabe' : e.description),
          subtitle: Text(
            '${dateLabel(e.expenseDate)} · ${euro(e.amount)} · bezahlt: ${payer?.name ?? '?'}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (paid > 0)
                Text('+${euro(paid)}',
                    style: const TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              if (owed > 0)
                Text('-${euro(owed)}',
                    style: const TextStyle(
                        color: _coral,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final net = totalPaid - totalOwed;

    return Scaffold(
      appBar: AppBar(title: Text(kasse.label)),
      body: ListView(
        children: [
          if (kasse.members.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(kasse.members.map((m) => m.name).join(' + '),
                  style: TextStyle(color: Colors.grey[700])),
            ),
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _cell('Gezahlt', totalPaid, Colors.black87),
                  _cell('Anteil', totalOwed, Colors.black87),
                  _cell('Saldo', net, net >= 0 ? _teal : _coral),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Beteiligte Ausgaben',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Keine Ausgaben.')),
            )
          else
            ...rows,
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _cell(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 2),
        Text(euro(value),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
