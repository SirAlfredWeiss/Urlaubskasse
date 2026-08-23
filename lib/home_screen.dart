import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'split_utils.dart';
import 'supabase_service.dart';

const _teal = Color(0xFF0E7C86);
const _coral = Color(0xFFE8663D);

const kDefaultCategories = [
  'Einkaufen',
  'Essengehen',
  'Cafe',
  'Auswärts trinken',
  'Snacks',
  'Transport',
  'Aktivitäten',
  'Shopping',
  'Unterkunft',
  'Sonstiges',
];
const kEinkaufCat = 'Einkaufen';
const kAuswaertsCats = ['Essengehen', 'Cafe', 'Auswärts trinken', 'Snacks'];

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
  List<Booking> _bookings = [];
  Person? _me;

  bool _loading = true;
  String? _error;
  int _tab = 0;

  Person? personById(String id) {
    for (final p in _persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---- meine Kasse ----
  String get _myKasse => _me == null ? '' : kasseLabelOf(_me!);
  Set<String> get _myMemberIds =>
      _me == null ? {} : kasseMemberIds(_me!, _persons);
  List<BudgetPeriod> get _myPeriods =>
      _periods.where((p) => (p.groupLabel ?? '').trim() == _myKasse).toList();
  bool get _hasBudget => _myPeriods.isNotEmpty;

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
      final bookings = await _service.fetchBookings(_trip!.id);

      // gespeicherte "wer bin ich"-Auswahl wiederherstellen
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('me_person_id');
      Person? me;
      for (final p in persons) {
        if (p.id == savedId) me = p;
      }

      setState(() {
        _persons = persons;
        _expenses = expenses;
        _periods = periods;
        _bookings = bookings;
        _me = me;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setMe(Person p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('me_person_id', p.id);
    setState(() => _me = p);
  }

  Future<void> _pickMe() async {
    final picked = await showDialog<Person>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Wer bist du?'),
        children: _persons
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, p),
                  child: Row(
                    children: [
                      _Avatar(person: p, size: 30),
                      const SizedBox(width: 12),
                      Text(p.name, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
    if (picked != null) await _setMe(picked);
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
        categories: _allCategories(),
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
              items: data.items,
              category: data.category,
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
              items: data.items,
              category: data.category,
            );
          }
        },
      ),
    );
    if (ok == true) await _loadTripData();
  }

  List<String> _allCategories() {
    final set = <String>{...kDefaultCategories};
    for (final e in _expenses) {
      final c = e.category?.trim() ?? '';
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList();
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
              title: const Text('Löschen', style: TextStyle(color: _coral)),
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
    if (_trip == null || _me == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BudgetSheet(
        kasseLabel: _myKasse,
        periods: _myPeriods,
        onAdd: (start, end, amount) => _service.addBudgetPeriod(
          tripId: _trip!.id,
          startDate: start,
          endDate: end,
          dailyAmount: amount,
          groupLabel: _myKasse,
        ),
        onDelete: (id) => _service.deleteBudgetPeriod(id),
      ),
    );
    if (changed == true) await _loadTripData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: _ErrorView(message: _error!, onRetry: _loadTrips));
    }
    if (_trip == null) {
      return const Scaffold(body: Center(child: Text('Keine Reise gefunden.')));
    }
    if (_me == null) {
      return Scaffold(body: _whoAmI());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_trip?.name ?? 'Urlaubskasse'),
        actions: [
          TextButton.icon(
            onPressed: _pickMe,
            icon: _Avatar(person: _me, size: 24),
            label: Text(_me?.name ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Budget',
            onPressed: _openBudgetSheet,
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTripData,
        child: _tab == 0
            ? _budgetView()
            : (_tab == 1 ? _settlementView() : _analysisView()),
      ),
      floatingActionButton: (_tab == 0 && _persons.isNotEmpty)
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
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Analyse'),
        ],
      ),
    );
  }

  // -------------------- "Wer bist du?" --------------------
  Widget _whoAmI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text('Wer bist du?',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Damit dein Budget für deine Kasse gilt.',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: _persons.map((p) {
                  return Card(
                    child: ListTile(
                      leading: _Avatar(person: p, size: 38),
                      title: Text(p.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      subtitle: Text('Kasse: ${kasseLabelOf(p)}'),
                      onTap: () => _setMe(p),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Budget / Tagesansicht (Kassen-Sicht) --------------------
  Widget _budgetView() {
    final days = tripDays(_myPeriods, _expenses);
    final tBudget = totalBudget(_myPeriods);
    var tShare = 0.0;
    for (final e in _expenses) {
      tShare += kasseShareOfExpense(e, _myMemberIds);
    }
    final tRest = tBudget - tShare;

    // Stand der bereits verstrichenen Tage (bis heute)
    final today = fmtDate(DateTime.now());
    var budgetSoFar = 0.0;
    var elapsed = 0;
    for (final d in tripDays(_myPeriods, const [])) {
      if (d.compareTo(today) <= 0) {
        budgetSoFar += dailyBudgetForDate(_myPeriods, d);
        elapsed++;
      }
    }
    var shareSoFar = 0.0;
    for (final e in _expenses) {
      final d = e.expenseDate ?? '';
      if (d.isNotEmpty && d.compareTo(today) <= 0) {
        shareSoFar += kasseShareOfExpense(e, _myMemberIds);
      }
    }
    final soFar = budgetSoFar - shareSoFar; // + = unter, - = ueber Budget

    final byDay = <String, List<Expense>>{};
    for (final e in _expenses) {
      byDay.putIfAbsent(e.expenseDate ?? '', () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
          color: !_hasBudget
              ? const Color(0xFFF3F1EC)
              : (tRest >= 0 ? const Color(0xFFEAF5F5) : const Color(0xFFFDECE6)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Gesamt · Kasse ${_myKasse}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (_hasBudget) _totalCell('Budget', tBudget, Colors.black87),
                    _totalCell('Dein Anteil', tShare, Colors.black87),
                    if (_hasBudget)
                      _totalCell('Rest', tRest, tRest >= 0 ? _teal : _coral),
                  ],
                ),
                if (_hasBudget) ...[
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bis heute ($elapsed ${elapsed == 1 ? 'Tag' : 'Tage'})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${soFar >= 0 ? '+' : ''}${euro(soFar)}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: soFar >= 0 ? _teal : _coral),
                          ),
                          Text(
                            soFar >= 0 ? 'unter Budget' : 'über Budget',
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (days.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: Text('Noch keine Ausgaben.')),
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
    final budget = dailyBudgetForDate(_myPeriods, day);
    var share = 0.0;
    for (final e in dayExpenses) {
      share += kasseShareOfExpense(e, _myMemberIds);
    }
    final rest = budget - share;
    final leftBg = !_hasBudget
        ? const Color(0xFFF5F4F0)
        : (rest >= 0 ? const Color(0xFFF1F7F7) : const Color(0xFFFBEEE9));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LINKS 25% : Budget/Anteil des Tages
            Expanded(
              flex: 25,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: leftBg,
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
                    if (_hasBudget) ...[
                      _kv('Budget', budget, Colors.black87),
                      _kv('Anteil', share, Colors.black54),
                      const Divider(height: 12),
                      _kv('Rest', rest, rest >= 0 ? _teal : _coral, bold: true),
                    ] else
                      _kv('Anteil', share, _teal, bold: true),
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
                        children: dayExpenses.map(_expenseRow).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseRow(Expense e) {
    final payer = personById(e.spentBy);
    final names = e.participants
        .map((p) => personById(p.personId)?.name ?? '?')
        .join(', ');
    final myShare = kasseShareOfExpense(e, _myMemberIds);
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.description.isEmpty ? 'Ausgabe' : e.description,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${names.isEmpty ? '' : '$names · '}gesamt ${euro(e.amount)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(euro(myShare),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _teal)),
                Text('dein Anteil',
                    style: TextStyle(fontSize: 9, color: Colors.grey[500])),
              ],
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
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

  // -------------------- Analyse (Kassen-Sicht) --------------------
  Widget _analysisView() {
    final memberIds = _myMemberIds;

    final catTotals = <String, double>{};
    final dateSet = <String>{};
    var expCount = 0;
    var maxExpense = 0.0;
    String maxExpenseLabel = '';
    for (final e in _expenses) {
      final share = kasseShareOfExpense(e, memberIds);
      if (share <= 0) continue;
      expCount++;
      final cat = (e.category != null && e.category!.trim().isNotEmpty)
          ? e.category!.trim()
          : 'Ohne Kategorie';
      catTotals[cat] = (catTotals[cat] ?? 0) + share;
      if ((e.expenseDate ?? '').isNotEmpty) dateSet.add(e.expenseDate!);
      if (share > maxExpense) {
        maxExpense = share;
        maxExpenseLabel = e.description.isEmpty ? 'Ausgabe' : e.description;
      }
    }
    var bookingShare = 0.0;
    var bookCount = 0;
    for (final b in _bookings) {
      final sh = kasseShareOfBooking(b, memberIds);
      if (sh <= 0) continue;
      bookingShare += sh;
      bookCount++;
      if ((b.bookingDate ?? '').isNotEmpty) dateSet.add(b.bookingDate!);
    }
    if (bookingShare > 0) {
      catTotals['Buchungen'] = (catTotals['Buchungen'] ?? 0) + bookingShare;
    }

    final total = catTotals.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Text('Noch keine Ausgaben zum Auswerten.'),
        ),
      );
    }
    final dayCount = dateSet.isEmpty ? 1 : dateSet.length;
    final perDay = total / dayCount;

    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Einkaufen vs Auswärts
    var einkauf = 0.0;
    var einkaufN = 0;
    var auswaerts = 0.0;
    var auswaertsN = 0;
    for (final e in _expenses) {
      final share = kasseShareOfExpense(e, memberIds);
      if (share <= 0) continue;
      final cat = e.category?.trim() ?? '';
      if (cat == kEinkaufCat) {
        einkauf += share;
        einkaufN++;
      } else if (kAuswaertsCats.contains(cat)) {
        auswaerts += share;
        auswaertsN++;
      }
    }
    final foodTotal = einkauf + auswaerts;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text('Analyse · Kasse ${_myKasse}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCell('Gesamt', euro(total)),
                _statCell('Positionen', '${expCount + bookCount}'),
                _statCell('Ø / Tag', euro(perDay)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text('Wofür ausgegeben',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
            child: Column(
              children:
                  sorted.map((e) => _catBar(e.key, e.value, total)).toList(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text('Einkaufen vs. Auswärts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: foodTotal <= 0
                ? const Text(
                    'Ordne Ausgaben den Kategorien Einkaufen / Essengehen / Cafe / Bar / Snacks zu, dann erscheint hier der Vergleich.',
                    style: TextStyle(color: Colors.grey),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            if (einkauf > 0)
                              Expanded(
                                flex: (einkauf * 100).round().clamp(1, 1000000),
                                child: Container(
                                  height: 26,
                                  color: _teal,
                                  alignment: Alignment.center,
                                  child: Text(
                                      '${(einkauf / foodTotal * 100).round()}%',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                ),
                              ),
                            if (auswaerts > 0)
                              Expanded(
                                flex:
                                    (auswaerts * 100).round().clamp(1, 1000000),
                                child: Container(
                                  height: 26,
                                  color: _coral,
                                  alignment: Alignment.center,
                                  child: Text(
                                      '${(auswaerts / foodTotal * 100).round()}%',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _legendDot(_teal, 'Einkaufen ${euro(einkauf)}'),
                          _legendDot(_coral, 'Auswärts ${euro(auswaerts)}'),
                        ],
                      ),
                      const Divider(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statCell('Ø / Einkauf',
                              einkaufN > 0 ? euro(einkauf / einkaufN) : '–'),
                          _statCell(
                              'Ø / Besuch',
                              auswaertsN > 0
                                  ? euro(auswaerts / auswaertsN)
                                  : '–'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statCell('Einkäufe', '$einkaufN'),
                          _statCell('Auswärts-Besuche', '$auswaertsN'),
                        ],
                      ),
                      if (einkaufN > 0 &&
                          auswaertsN > 0 &&
                          einkauf / einkaufN > 0) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECE6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Auswärts kostet im Schnitt das '
                            '${((auswaerts / auswaertsN) / (einkauf / einkaufN)).toStringAsFixed(1).replaceAll('.', ',')}-fache '
                            'eines Einkaufs.',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: Color(0xFFB23A16)),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        if (maxExpense > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text('Teuerster Posten: $maxExpenseLabel (${euro(maxExpense)})',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
      ],
    );
  }

  Widget _statCell(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _legendDot(Color c, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }

  Widget _catBar(String cat, double value, double total) {
    final pct = total > 0 ? value / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(cat,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${euro(value)}  ·  ${(pct * 100).round()}%',
                  style: const TextStyle(fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: const Color(0xFFEDEBE6),
              valueColor: const AlwaysStoppedAnimation(_teal),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bookingsSection() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
        child: Row(
          children: [
            const Text('Buchungen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openBookingForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Buchung'),
            ),
          ],
        ),
      ),
      Card(
        child: _bookings.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: Center(
                    child: Text('Noch keine Buchungen.',
                        style: TextStyle(color: Colors.grey))),
              )
            : Column(
                children: _bookings.map((b) {
                  final payer = personById(b.bookedBy);
                  return ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BookingDetailScreen(booking: b, persons: _persons),
                      ),
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEAF5F5),
                      child: Icon(Icons.confirmation_number_outlined,
                          color: _teal, size: 20),
                    ),
                    title: Text(b.title),
                    subtitle: Text(
                      '${dateLabel(b.bookingDate)} · bezahlt: ${payer?.name ?? '?'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(euro(b.amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _openBookingForm(existing: b);
                            } else if (v == 'delete') {
                              _deleteBooking(b);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Bearbeiten')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Löschen')),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    ];
  }

  Future<void> _openBookingForm({Booking? existing}) async {
    if (_trip == null || _persons.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BookingSheet(
        persons: _persons,
        existing: existing,
        defaultDate: fmtDate(DateTime.now()),
        onSubmit: (data, id) async {
          if (id == null) {
            await _service.addBooking(
              tripId: _trip!.id,
              bookedBy: data.bookedBy,
              title: data.title,
              amount: data.amount,
              bookingDate: data.bookingDate,
              ticketNumber: data.ticketNumber,
              note: data.note,
              participantIds: data.participantIds,
            );
          } else {
            await _service.updateBooking(
              id: id,
              bookedBy: data.bookedBy,
              title: data.title,
              amount: data.amount,
              bookingDate: data.bookingDate,
              ticketNumber: data.ticketNumber,
              note: data.note,
              participantIds: data.participantIds,
            );
          }
        },
      ),
    );
    if (ok == true) await _loadTripData();
  }

  Future<void> _deleteBooking(Booking b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buchung löschen?'),
        content: Text(b.title),
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
      await _service.deleteBooking(b.id);
      await _loadTripData();
    }
  }

  // -------------------- Abrechnung (Kassen) --------------------
  Widget _settlementView() {
    final kassen = computeKassen(_persons, _expenses, bookings: _bookings);
    final transfers =
        computeKasseSettlement(_persons, _expenses, bookings: _bookings);
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
                        kasse: k,
                        persons: _persons,
                        expenses: _expenses,
                        bookings: _bookings),
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
        ..._bookingsSection(),
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
  final List<Map<String, dynamic>> items; // nur bei "feste Beträge" (Kassenzettel)
  final String? category;
  NewExpense({
    required this.spentBy,
    required this.amount,
    required this.description,
    required this.expenseDate,
    required this.splitMethod,
    required this.participants,
    this.items = const [],
    this.category,
  });
}

class _PosItem {
  final TextEditingController amount;
  final Set<String> personIds;
  _PosItem({String amountText = '', Set<String>? ids})
      : amount = TextEditingController(text: amountText),
        personIds = ids ?? <String>{};
}

class ExpenseSheet extends StatefulWidget {
  final List<Person> persons;
  final Expense? existing;
  final String defaultDate;
  final List<String> categories;
  final Future<void> Function(NewExpense data, String? existingId) onSubmit;
  const ExpenseSheet({
    super.key,
    required this.persons,
    required this.defaultDate,
    required this.onSubmit,
    this.categories = const [],
    this.existing,
  });

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final TextEditingController _desc;
  late final TextEditingController _amount;
  final Map<String, TextEditingController> _shares = {};
  final List<_PosItem> _items = [];

  Person? _payer;
  late DateTime _date;
  String _method = 'equal';
  final Set<String> _selected = {};
  String? _category;
  late List<String> _cats;
  bool _saving = false;
  String? _msg;

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Neue Kategorie'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'z. B. Eis'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Hinzufügen')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() {
        if (!_cats.contains(name)) _cats.add(name);
        _category = name;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category;
    _cats = [...widget.categories];
    if (_category != null && _category!.isNotEmpty && !_cats.contains(_category)) {
      _cats.add(_category!);
    }
    _desc = TextEditingController(text: e?.description ?? '');
    _amount = TextEditingController(
        text: e != null ? _fmtNum(e.amount) : '');
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
          _shares[p.personId] =
              TextEditingController(text: _fmtNum(p.share!));
        }
      }
      // Kassenzettel-Positionen vorbelegen
      if (_method == 'exact') {
        if (e.items.isNotEmpty) {
          for (final it in e.items) {
            _items.add(_PosItem(
                amountText: _fmtNum(it.amount),
                ids: it.personIds.toSet()));
          }
        } else {
          // Alt-Ausgabe ohne Positionen: aus festen Beträgen rekonstruieren
          for (final p in e.participants) {
            _items.add(_PosItem(
                amountText: _fmtNum(p.share ?? 0), ids: {p.personId}));
          }
        }
      }
    }
    _payer ??= widget.persons.isNotEmpty ? widget.persons.first : null;
    if (_method == 'exact' && _items.isEmpty) _items.add(_PosItem());
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _shares.values) {
      c.dispose();
    }
    for (final it in _items) {
      it.amount.dispose();
    }
    super.dispose();
  }

  String _fmtNum(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  TextEditingController _shareCtrl(String id) =>
      _shares.putIfAbsent(id, () => TextEditingController(text: '1'));

  // ---- Kassenzettel-Berechnung (cent-genau) ----
  Map<String, int> _perPersonCents() {
    final totals = <String, int>{};
    for (final it in _items) {
      final a =
          double.tryParse(it.amount.text.trim().replaceAll(',', '.')) ?? 0;
      final cents = (a * 100).round();
      final ids = it.personIds.toList();
      if (cents <= 0 || ids.isEmpty) continue;
      final base = cents ~/ ids.length;
      final rem = cents - base * ids.length;
      for (var i = 0; i < ids.length; i++) {
        final c = base + (i < rem ? 1 : 0);
        totals[ids[i]] = (totals[ids[i]] ?? 0) + c;
      }
    }
    return totals;
  }

  Future<void> _save() async {
    final desc = _desc.text.trim();
    if (desc.isEmpty) {
      setState(() => _msg = 'Bitte einen Zweck angeben.');
      return;
    }
    if (_payer == null) {
      setState(() => _msg = 'Bitte Zahler wählen.');
      return;
    }

    double amount;
    String splitMethod = _method;
    List<Map<String, dynamic>> participants;
    List<Map<String, dynamic>> items = const [];

    if (_method == 'exact') {
      final totals = _perPersonCents();
      if (totals.isEmpty) {
        setState(() =>
            _msg = 'Bitte mindestens eine Position mit Betrag und Personen.');
        return;
      }
      amount = totals.values.fold(0, (a, b) => a + b) / 100.0;
      participants = totals.entries
          .map((e) => {'person_id': e.key, 'share': e.value / 100.0})
          .toList();
      items = _items
          .where((it) {
            final a = double.tryParse(
                    it.amount.text.trim().replaceAll(',', '.')) ??
                0;
            return a > 0 && it.personIds.isNotEmpty;
          })
          .map((it) => {
                'amount':
                    double.parse(it.amount.text.trim().replaceAll(',', '.')),
                'person_ids': it.personIds.toList(),
              })
          .toList();
    } else {
      amount = double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
      if (amount <= 0) {
        setState(() => _msg = 'Bitte einen gültigen Betrag angeben.');
        return;
      }
      if (_selected.isEmpty) {
        setState(() => _msg = 'Bitte Beteiligte wählen.');
        return;
      }
      participants = _selected.map((id) {
        double? share;
        if (_method != 'equal') {
          share =
              double.tryParse(_shareCtrl(id).text.trim().replaceAll(',', '.'));
        }
        return {'person_id': id, 'share': share};
      }).toList();
    }

    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      await widget.onSubmit(
        NewExpense(
          spentBy: _payer!.id,
          amount: amount,
          description: desc,
          expenseDate: fmtDate(_date),
          splitMethod: splitMethod,
          participants: participants,
          items: items,
          category: _category,
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
    final exact = _method == 'exact';
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
                if (!exact)
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Betrag (€)',
                          border: OutlineInputBorder()),
                    ),
                  )
                else
                  const Expanded(
                    child: Text('Betrag = Summe der Positionen',
                        style: TextStyle(color: Colors.grey)),
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
                  label: Text(dateLabel(fmtDate(_date))),
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
            const Text('Kategorie',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ..._cats.map((c) => ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    )),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Neu'),
                  onPressed: _addCategory,
                ),
              ],
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
                DropdownMenuItem(
                    value: 'exact', child: Text('feste Beträge (Kassenzettel)')),
              ],
              onChanged: (v) => setState(() {
                _method = v ?? 'equal';
                if (_method == 'exact' && _items.isEmpty) {
                  _items.add(_PosItem());
                }
              }),
            ),
            const SizedBox(height: 12),
            if (!exact) ..._splitPersonUI() else ..._kassenzettelUI(),
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
                      : (editing
                          ? 'Änderungen speichern'
                          : 'Ausgabe speichern')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- UI: gleichmäßig / Anteile ----
  List<Widget> _splitPersonUI() {
    return [
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
      if (_method == 'shares' && _selected.isNotEmpty) ...[
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixText: 'x',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ];
  }

  // ---- UI: Kassenzettel-Rechner ----
  List<Widget> _kassenzettelUI() {
    final totals = _perPersonCents();
    final sum = totals.values.fold(0, (a, b) => a + b) / 100.0;

    return [
      const Text('Positionen',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('Jede Position wird gleichmäßig auf die gewählten Personen geteilt.',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 8),
      ...List.generate(_items.length, (i) => _posRow(i)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _items.add(_PosItem())),
          icon: const Icon(Icons.add),
          label: const Text('Position'),
        ),
      ),
      const Divider(),
      if (totals.isEmpty)
        const Text('Noch keine gültigen Positionen.',
            style: TextStyle(color: Colors.grey))
      else ...[
        const Text('Ergebnis', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...widget.persons.where((p) => (totals[p.id] ?? 0) > 0).map((p) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _Avatar(person: p, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name)),
                Text(euro((totals[p.id] ?? 0) / 100.0),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Gesamt', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(euro(sum),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _teal)),
          ],
        ),
      ],
    ];
  }

  Widget _posRow(int i) {
    final it = _items[i];
    final allSelected = it.personIds.length == widget.persons.length &&
        widget.persons.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 100,
                child: TextField(
                  controller: it.amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixText: '€ ',
                    hintText: '0,00',
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                onPressed: _items.length <= 1
                    ? null
                    : () => setState(() {
                          _items[i].amount.dispose();
                          _items.removeAt(i);
                        }),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text('Alle'),
                selected: allSelected,
                onSelected: (v) => setState(() {
                  it.personIds.clear();
                  if (v) it.personIds.addAll(widget.persons.map((p) => p.id));
                }),
              ),
              ...widget.persons.map((p) {
                final sel = it.personIds.contains(p.id);
                return FilterChip(
                  avatar: _Avatar(person: p, size: 16),
                  label: Text(p.name),
                  selected: sel,
                  onSelected: (v) => setState(() {
                    v ? it.personIds.add(p.id) : it.personIds.remove(p.id);
                  }),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================ Budget-Zeitraeume ============================

class BudgetSheet extends StatefulWidget {
  final String kasseLabel;
  final List<BudgetPeriod> periods;
  final Future<void> Function(String start, String end, double amount) onAdd;
  final Future<void> Function(String id) onDelete;
  const BudgetSheet({
    super.key,
    required this.kasseLabel,
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
            Text('Budget · Kasse ${widget.kasseLabel}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.periods.isEmpty)
              const Text('Noch kein Budget-Zeitraum für diese Kasse.',
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
  final List<Booking> bookings;
  const KasseDetailScreen({
    super.key,
    required this.kasse,
    required this.persons,
    required this.expenses,
    this.bookings = const [],
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

    for (final b in bookings) {
      final ids = b.participantIds;
      final owed = ids.isEmpty
          ? 0.0
          : ids.where(memberIds.contains).length * (b.amount / ids.length);
      final paid = memberIds.contains(b.bookedBy) ? b.amount : 0.0;
      if (paid == 0 && owed == 0) continue;

      totalPaid += paid;
      totalOwed += owed;

      final payer = _p(b.bookedBy);
      rows.add(
        ListTile(
          leading: const CircleAvatar(
            radius: 15,
            backgroundColor: Color(0xFFEAF5F5),
            child: Icon(Icons.confirmation_number_outlined,
                size: 16, color: _teal),
          ),
          title: Text(b.title),
          subtitle: Text(
            'Buchung · ${euro(b.amount)} · bezahlt: ${payer?.name ?? '?'}',
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

// ============================ Buchungs-Detail ============================

class BookingDetailScreen extends StatelessWidget {
  final Booking booking;
  final List<Person> persons;
  const BookingDetailScreen(
      {super.key, required this.booking, required this.persons});

  Person? _p(String id) {
    for (final p in persons) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ids = booking.participantIds;
    final each = ids.isEmpty ? 0.0 : booking.amount / ids.length;
    final payer = _p(booking.bookedBy);

    return Scaffold(
      appBar: AppBar(title: Text(booking.title)),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(euro(booking.amount),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _teal)),
                  const SizedBox(height: 6),
                  Text(
                    '${dateLabel(booking.bookingDate)}  ·  bezahlt von ${payer?.name ?? '?'}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  if ((booking.ticketNumber ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Ticket: ${booking.ticketNumber}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('Aufteilung (gleichmäßig)',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (ids.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Keine Beteiligten hinterlegt.')),
            )
          else
            ...ids.map((id) {
              final p = _p(id);
              return ListTile(
                leading: _Avatar(person: p, size: 30),
                title: Text(p?.name ?? '?'),
                trailing: Text(euro(each),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _coral)),
              );
            }),
          if ((booking.note ?? '').isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Notiz', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(booking.note!),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================ Buchungs-Formular ============================

class NewBooking {
  final String bookedBy;
  final String title;
  final double amount;
  final String bookingDate;
  final String? ticketNumber;
  final String? note;
  final List<String> participantIds;
  NewBooking({
    required this.bookedBy,
    required this.title,
    required this.amount,
    required this.bookingDate,
    this.ticketNumber,
    this.note,
    required this.participantIds,
  });
}

class BookingSheet extends StatefulWidget {
  final List<Person> persons;
  final Booking? existing;
  final String defaultDate;
  final Future<void> Function(NewBooking data, String? existingId) onSubmit;
  const BookingSheet({
    super.key,
    required this.persons,
    required this.defaultDate,
    required this.onSubmit,
    this.existing,
  });

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _ticket;
  late final TextEditingController _note;

  Person? _payer;
  late DateTime _date;
  final Set<String> _selected = {};
  bool _saving = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _title = TextEditingController(text: b?.title ?? '');
    _amount = TextEditingController(
        text: b != null
            ? b.amount.toStringAsFixed(2).replaceAll('.', ',')
            : '');
    _ticket = TextEditingController(text: b?.ticketNumber ?? '');
    _note = TextEditingController(text: b?.note ?? '');
    _date =
        DateTime.tryParse(b?.bookingDate ?? widget.defaultDate) ?? DateTime.now();
    if (b != null) {
      for (final p in widget.persons) {
        if (p.id == b.bookedBy) _payer = p;
      }
      _selected.addAll(b.participantIds);
    }
    _payer ??= widget.persons.isNotEmpty ? widget.persons.first : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _ticket.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;
    if (title.isEmpty || amount <= 0) {
      setState(() => _msg = 'Bitte Titel und gültigen Betrag angeben.');
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
      await widget.onSubmit(
        NewBooking(
          bookedBy: _payer!.id,
          title: title,
          amount: amount,
          bookingDate: fmtDate(_date),
          ticketNumber:
              _ticket.text.trim().isEmpty ? null : _ticket.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          participantIds: _selected.toList(),
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
            Text(editing ? 'Buchung bearbeiten' : 'Neue Buchung',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Titel (z. B. Unterkunft Rom)',
                  border: OutlineInputBorder()),
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
                  label: Text(dateLabel(fmtDate(_date))),
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
                const Text('Beteiligt (gleichmäßig geteilt)',
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
            const SizedBox(height: 12),
            TextField(
              controller: _ticket,
              decoration: const InputDecoration(
                  labelText: 'Ticket-Nr. (optional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notiz (optional)', border: OutlineInputBorder()),
            ),
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
                      : (editing
                          ? 'Änderungen speichern'
                          : 'Buchung speichern')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
