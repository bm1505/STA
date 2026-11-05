import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FleetManagementScreen extends StatefulWidget {
  const FleetManagementScreen({super.key});

  @override
  State<FleetManagementScreen> createState() => _FleetManagementScreenState();
}

class _FleetManagementScreenState extends State<FleetManagementScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  final NumberFormat _money = NumberFormat('#,##0');
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _fuelLogs = [];
  List<Map<String, dynamic>> _maintenance = [];
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _liveDrivers = [];
  List<Map<String, dynamic>> _assignments = [];
  StreamSubscription<List<Map<String, dynamic>>>? _locationSubscription;
  Map<String, dynamic> _metrics = {};
  String? _organizationId;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    try {
      final result = await _db.rpc('sta_list_my_organizations');
      final organizations = (result as List)
          .map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (!mounted) return;
      setState(() {
        _organizations = organizations;
        _organizationId ??= organizations.isNotEmpty ? organizations.first['id'].toString() : null;
        _loading = false;
      });
      if (_organizationId != null) await _loadOrganizationData();
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _showMessage('Could not load organizations: $error');
    }
  }

  Future<void> _loadOrganizationData() async {
    final id = _organizationId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        _db.rpc('sta_owner_dashboard', params: {'p_org_id': id}),
        _db.from('fleet_vehicles').select().eq('organization_id', id).order('created_at', ascending: false),
        _db.from('transport_branches').select().eq('organization_id', id).order('created_at', ascending: false),
        _db.from('fleet_fuel_logs').select().eq('organization_id', id).order('created_at', ascending: false).limit(8),
        _db.from('fleet_maintenance_records').select().eq('organization_id', id).order('created_at', ascending: false).limit(8),
        _db.from('transport_contracts').select().eq('organization_id', id).order('created_at', ascending: false).limit(8),
        _db.rpc('sta_list_org_members', params: {'p_org_id': id}),
        _db.rpc('sta_org_live_locations', params: {'p_org_id': id}),
        _db.rpc('sta_list_org_assignments', params: {'p_org_id': id}),
      ]);
      final metricRows = results[0] as List;
      if (!mounted) return;
      setState(() {
        _metrics = metricRows.isEmpty ? {} : Map<String, dynamic>.from(metricRows.first as Map);
        _vehicles = (results[1] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _branches = (results[2] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _fuelLogs = (results[3] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _maintenance = (results[4] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _contracts = (results[5] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _members = (results[6] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _liveDrivers = (results[7] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _assignments = (results[8] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _busy = false;
      });
      await _locationSubscription?.cancel();
      _locationSubscription = _db.from('driver_locations')
          .stream(primaryKey: ['driver_id'])
          .listen((_) => _loadLiveDrivers(), onError: (error) {
        debugPrint('Fleet location stream failed: $error');
      });
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _showMessage('Could not refresh fleet data: $error');
    }
  }

  Future<void> _loadLiveDrivers() async {
    final id = _organizationId;
    if (id == null) return;
    try {
      final result = await _db.rpc('sta_org_live_locations', params: {'p_org_id': id});
      final drivers = (result as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (mounted) setState(() => _liveDrivers = drivers);
    } catch (error) {
      debugPrint('Fleet live location refresh failed: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _currency(dynamic value) =>
      'TZS ${_money.format((value as num?)?.round() ?? 0)}';

  Future<void> _createOrganization() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    var type = 'transport_company';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create transport organization'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Organization name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Organization type'),
                items: const [
                  DropdownMenuItem(value: 'vehicle_owner', child: Text('Vehicle owner')),
                  DropdownMenuItem(value: 'transport_company', child: Text('Transport company')),
                ],
                onChanged: (value) => setDialogState(() => type = value ?? type),
              ),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      try {
        final id = await _db.rpc('sta_create_transport_organization', params: {
          'p_name': name.text.trim(),
          'p_organization_type': type,
          'p_country_code': 'TZ',
          'p_phone_number': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'p_email': email.text.trim().isEmpty ? null : email.text.trim(),
        });
        _organizationId = id.toString();
        await _loadOrganizations();
      } catch (error) {
        _showMessage('Could not create organization: $error');
      }
    }
    name.dispose(); phone.dispose(); email.dispose();
  }

  Future<void> _addVehicle() async {
    final orgId = _organizationId;
    if (orgId == null) return;
    final plate = TextEditingController();
    final make = TextEditingController();
    final model = TextEditingController();
    final year = TextEditingController();
    final capacity = TextEditingController(text: '4');
    var type = 'Car';
    String? branchId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add vehicle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Registration number *')),
              TextField(controller: make, decoration: const InputDecoration(labelText: 'Make')),
              TextField(controller: model, decoration: const InputDecoration(labelText: 'Model')),
              TextField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Manufacture year')),
              TextField(controller: capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Passenger capacity')),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: const ['Bodaboda','Bajaji','Car','XL','STA Send']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (value) => setDialogState(() => type = value ?? type),
              ),
              if (_branches.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: branchId,
                  decoration: const InputDecoration(labelText: 'Branch (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No branch')),
                    ..._branches.map((b) => DropdownMenuItem<String?>(
                      value: b['id'].toString(), child: Text(b['name'].toString()))),
                  ],
                  onChanged: (value) => setDialogState(() => branchId = value),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save vehicle')),
          ],
        ),
      ),
    );
    if (accepted == true && plate.text.trim().isNotEmpty) {
      try {
        await _db.rpc('sta_create_fleet_vehicle', params: {
          'p_org_id': orgId,
          'p_registration_number': plate.text.trim(),
          'p_vehicle_type': type,
          'p_make': make.text.trim().isEmpty ? null : make.text.trim(),
          'p_model': model.text.trim().isEmpty ? null : model.text.trim(),
          'p_year': int.tryParse(year.text),
          'p_capacity': int.tryParse(capacity.text) ?? 4,
          'p_branch_id': branchId,
        });
        await _loadOrganizationData();
      } catch (error) {
        _showMessage('Could not add vehicle: $error');
      }
    }
    plate.dispose(); make.dispose(); model.dispose(); year.dispose(); capacity.dispose();
  }

  Future<void> _addBranch() async {
    final orgId = _organizationId;
    if (orgId == null) return;
    final name = TextEditingController();
    final region = TextEditingController();
    final city = TextEditingController();
    final address = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add branch'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Branch name *')),
          TextField(controller: region, decoration: const InputDecoration(labelText: 'Region')),
          TextField(controller: city, decoration: const InputDecoration(labelText: 'City')),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      try {
        await _db.rpc('sta_create_transport_branch', params: {
          'p_org_id': orgId, 'p_name': name.text.trim(),
          'p_region': region.text.trim(), 'p_city': city.text.trim(), 'p_address': address.text.trim(),
        });
        await _loadOrganizationData();
      } catch (error) { _showMessage('Could not add branch: $error'); }
    }
    name.dispose(); region.dispose(); city.dispose(); address.dispose();
  }

  Map<String, dynamic>? _assignmentForVehicle(String vehicleId) {
    for (final assignment in _assignments) {
      if (assignment['vehicle_id']?.toString() == vehicleId) return assignment;
    }
    return null;
  }

  Future<void> _unassignDriver(String assignmentId) async {
    try {
      await _db.rpc('sta_unassign_driver_vehicle', params: {'p_assignment_id': assignmentId});
      await _loadOrganizationData();
    } catch (error) {
      _showMessage('Could not unassign driver: $error');
    }
  }

  Future<void> _assignDriver(String vehicleId) async {
    final orgId = _organizationId;
    if (orgId == null) return;
    try {
      final result = await _db.rpc('sta_search_available_drivers', params: {
        'p_org_id': orgId, 'p_query': '',
      });
      final drivers = (result as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      if (!mounted) return;
      if (drivers.isEmpty) {
        _showMessage('No available verified drivers were found.');
        return;
      }
      await showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF17212A),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Assign a verified driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ...drivers.map((driver) => ListTile(
                leading: const Icon(Icons.person, color: Color(0xFFFFD166)),
                title: Text(driver['driver_name']?.toString() ?? 'Driver', style: const TextStyle(color: Colors.white)),
                subtitle: Text('${driver['phone_number'] ?? ''} · ${driver['is_online'] == true ? 'Online' : 'Offline'}',
                  style: const TextStyle(color: Colors.white54)),
                onTap: () async {
                  try {
                    await _db.rpc('sta_assign_driver_vehicle', params: {
                      'p_org_id': orgId,
                      'p_vehicle_id': vehicleId,
                      'p_driver_id': driver['driver_id'],
                    });
                    if (context.mounted) Navigator.pop(context);
                    await _loadOrganizationData();
                  } catch (error) { _showMessage('Could not assign driver: $error'); }
                },
              )),
            ],
          ),
        ),
      );
    } catch (error) { _showMessage('Could not load verified drivers: $error'); }
  }

  Future<void> _addMember() async {
    final orgId = _organizationId;
    if (orgId == null) return;
    final query = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find STA team member'),
        content: TextField(
          controller: query,
          decoration: const InputDecoration(labelText: 'Name, email or phone (at least 3 characters)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Search')),
        ],
      ),
    );
    if (accepted != true) { query.dispose(); return; }
    try {
      final result = await _db.rpc('sta_search_org_users', params: {
        'p_org_id': orgId, 'p_query': query.text.trim(),
      });
      final matches = (result as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (matches.isEmpty) {
        _showMessage('No active STA account matched that search.');
        return;
      }
      if (!mounted) return;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: const Color(0xFF17212A),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Select team member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ...matches.map((member) => ListTile(
                title: Text(member['display_name']?.toString() ?? 'STA user', style: const TextStyle(color: Colors.white)),
                subtitle: Text('${member['email'] ?? member['phone_number'] ?? ''} · ${member['account_role'] ?? ''}',
                  style: const TextStyle(color: Colors.white54)),
                onTap: () => Navigator.pop(context, member),
              )),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      var role = 'fleet_manager';
      final add = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Add ${selected['display_name']}'),
            content: DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Organization role'),
              items: const [
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'fleet_manager', child: Text('Fleet manager')),
                DropdownMenuItem(value: 'finance', child: Text('Finance')),
                DropdownMenuItem(value: 'dispatcher', child: Text('Dispatcher')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
              ],
              onChanged: (value) => setDialogState(() => role = value ?? role),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add member')),
            ],
          ),
        ),
      );
      if (add == true) {
        await _db.rpc('sta_add_org_member', params: {
          'p_org_id': orgId,
          'p_user_id': selected['user_id'],
          'p_role': role,
        });
        await _loadOrganizationData();
      }
    } catch (error) {
      _showMessage('Could not add team member: $error');
    } finally {
      query.dispose();
    }
  }

  Future<void> _logFuel() async {
    final orgId = _organizationId;
    if (orgId == null || _vehicles.isEmpty) { _showMessage('Add a vehicle first.'); return; }
    final quantity = TextEditingController();
    final price = TextEditingController();
    final odometer = TextEditingController();
    final station = TextEditingController();
    String vehicleId = _vehicles.first['id'].toString();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log fuel'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: vehicleId,
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'].toString(), child: Text(v['registration_number'].toString()))).toList(),
              onChanged: (v) => setDialogState(() => vehicleId = v ?? vehicleId),
              decoration: const InputDecoration(labelText: 'Vehicle'),
            ),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Litres')),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price per litre (TZS)')),
            TextField(controller: odometer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Odometer (km)')),
            TextField(controller: station, decoration: const InputDecoration(labelText: 'Fuel station')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save log')),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await _db.rpc('sta_log_vehicle_fuel', params: {
          'p_org_id': orgId, 'p_vehicle_id': vehicleId,
          'p_quantity_liters': double.parse(quantity.text),
          'p_unit_price': double.parse(price.text),
          'p_odometer_km': double.tryParse(odometer.text),
          'p_fuel_station': station.text.trim(),
        });
        await _loadOrganizationData();
      } catch (error) { _showMessage('Fuel log failed: $error'); }
    }
    quantity.dispose(); price.dispose(); odometer.dispose(); station.dispose();
  }

  Future<void> _scheduleMaintenance() async {
    final orgId = _organizationId;
    if (orgId == null || _vehicles.isEmpty) { _showMessage('Add a vehicle first.'); return; }
    final type = TextEditingController();
    final description = TextEditingController();
    final cost = TextEditingController(text: '0');
    String vehicleId = _vehicles.first['id'].toString();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule maintenance'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: vehicleId,
              items: _vehicles.map((v) => DropdownMenuItem(value: v['id'].toString(), child: Text(v['registration_number'].toString()))).toList(),
              onChanged: (v) => setDialogState(() => vehicleId = v ?? vehicleId),
              decoration: const InputDecoration(labelText: 'Vehicle'),
            ),
            TextField(controller: type, decoration: const InputDecoration(labelText: 'Maintenance type')),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Estimated cost (TZS)')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Schedule')),
          ],
        ),
      ),
    );
    if (accepted == true && type.text.trim().isNotEmpty) {
      try {
        await _db.rpc('sta_create_maintenance_record', params: {
          'p_org_id': orgId, 'p_vehicle_id': vehicleId,
          'p_maintenance_type': type.text.trim(),
          'p_description': description.text.trim(),
          'p_cost': double.tryParse(cost.text) ?? 0,
        });
        await _loadOrganizationData();
      } catch (error) { _showMessage('Maintenance schedule failed: $error'); }
    }
    type.dispose(); description.dispose(); cost.dispose();
  }

  Future<void> _addContract() async {
    final orgId = _organizationId;
    if (orgId == null) return;
    final client = TextEditingController();
    final reference = TextEditingController();
    final value = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add transport contract'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: client, decoration: const InputDecoration(labelText: 'Client name')),
          TextField(controller: reference, decoration: const InputDecoration(labelText: 'Contract reference')),
          TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Contract value (TZS)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save contract')),
        ],
      ),
    );
    if (accepted == true && client.text.trim().isNotEmpty) {
      try {
        await _db.rpc('sta_create_transport_contract', params: {
          'p_org_id': orgId,
          'p_client_name': client.text.trim(),
          'p_contract_reference': reference.text.trim(),
          'p_contract_value': double.tryParse(value.text),
        });
        await _loadOrganizationData();
      } catch (error) { _showMessage('Contract could not be saved: $error'); }
    }
    client.dispose(); reference.dispose(); value.dispose();
  }

  Future<void> _showAiInsights() async {
    final id = _organizationId;
    if (id == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Analyzing real fleet records...')]),
      ),
    );
    var loadingDialogOpen = true;
    try {
      final response = await _db.functions.invoke('sta-ai', body: {
        'action': 'fleet_insights', 'organizationId': id,
      });
      if (mounted && loadingDialogOpen) {
        Navigator.pop(context);
        loadingDialogOpen = false;
      }
      if (response.status != 200 || response.data is! Map) throw StateError('AI insights unavailable');
      final insight = response.data['insights']?.toString() ?? 'No insight was returned.';
      if (!mounted) return;
      showDialog(context: context, builder: (context) => AlertDialog(
        title: const Text('STA Fleet Intelligence'),
        content: SingleChildScrollView(child: Text(insight)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (error) {
      if (mounted && loadingDialogOpen) Navigator.pop(context);
      _showMessage('Fleet AI is unavailable: $error');
    }
  }

  Widget _metric(String title, dynamic value, {bool money = false}) {
    final text = money ? _currency(value) : (value ?? 0).toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1D2B36), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 7),
        Text(text, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );
  }

  Widget _sectionTitle(String title, VoidCallback? action, String actionText) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(children: [
      Expanded(child: Text(title, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
      if (action != null) TextButton(onPressed: action, child: Text(actionText)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: Color(0xFF101820), body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: Text('Fleet & Transport', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _loadOrganizations, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _showAiInsights, icon: const Icon(Icons.auto_awesome, color: Color(0xFFFFD166))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrganization,
        icon: const Icon(Icons.add_business),
        label: const Text('Organization'),
      ),
      body: _organizations.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.directions_bus_filled_outlined, color: Color(0xFFFFD166), size: 54),
                const SizedBox(height: 14),
                const Text('Create a vehicle owner account or transport company to manage vehicles, drivers and operating costs.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _createOrganization, icon: const Icon(Icons.add), label: const Text('Create organization')),
              ]),
            ))
          : RefreshIndicator(
              onRefresh: _loadOrganizationData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  DropdownButtonFormField<String>(
                    value: _organizationId,
                    dropdownColor: const Color(0xFF1D2B36),
                    decoration: const InputDecoration(labelText: 'Organization', labelStyle: TextStyle(color: Colors.white60)),
                    style: const TextStyle(color: Colors.white),
                    items: _organizations.map((org) => DropdownMenuItem(
                      value: org['id'].toString(),
                      child: Text(org['name']?.toString() ?? 'Organization'),
                    )).toList(),
                    onChanged: (value) async {
                      setState(() => _organizationId = value);
                      await _loadOrganizationData();
                    },
                  ),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.8,
                    children: [
                      _metric('Vehicles', _metrics['vehicle_count']),
                      _metric('Active vehicles', _metrics['active_vehicle_count']),
                      _metric('Assigned drivers', _metrics['assigned_driver_count']),
                      _metric('Completed trips', _metrics['trip_count']),
                      _metric('Gross ride revenue', _metrics['gross_revenue'], money: true),
                      _metric('Fuel costs', _metrics['fuel_cost'], money: true),
                      _metric('Maintenance costs', _metrics['maintenance_cost'], money: true),
                      _metric('Operating balance*', _metrics['operating_balance'], money: true),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('*Before salaries, insurance, tax and other operating costs.',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                  _sectionTitle('Vehicles', _addVehicle, 'Add vehicle'),
                  if (_vehicles.isEmpty)
                    const Text('No vehicles have been registered.', style: TextStyle(color: Colors.white54))
                  else
                    ..._vehicles.map((vehicle) {
                      final assignment = _assignmentForVehicle(vehicle['id'].toString());
                      return Card(
                        color: const Color(0xFF1D2B36),
                        child: ListTile(
                          leading: const Icon(Icons.directions_car, color: Color(0xFFFFD166)),
                          title: Text(vehicle['registration_number']?.toString() ?? 'Vehicle',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            vehicle['vehicle_type']?.toString() ?? '',
                            [vehicle['make'], vehicle['model']].where((v) => v != null && v.toString().isNotEmpty).join(' '),
                            'Status: ${vehicle['status']}',
                            if (vehicle['current_odometer_km'] != null) 'Odometer: ${vehicle['current_odometer_km']} km',
                            if (assignment != null) 'Driver: ${assignment['driver_name']}',
                          ].where((v) => v.isNotEmpty).join(' · '),
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: IconButton(
                            tooltip: assignment == null ? 'Assign driver' : 'Unassign driver',
                            onPressed: assignment == null
                                ? () => _assignDriver(vehicle['id'].toString())
                                : () => _unassignDriver(assignment['assignment_id'].toString()),
                            icon: Icon(
                              assignment == null ? Icons.person_add_alt_1 : Icons.person_remove_alt_1,
                              color: const Color(0xFFFFD166),
                            ),
                          ),
                        ),
                      );
                    }),
                  _sectionTitle('Live assigned drivers', null, ''),
                  if (_liveDrivers.isEmpty)
                    const Text('No assigned driver has a recent live location.', style: TextStyle(color: Colors.white54))
                  else
                    ..._liveDrivers.map((driver) {
                      final updated = DateTime.tryParse(driver['recorded_at']?.toString() ?? '');
                      return ListTile(
                        leading: const Icon(Icons.gps_fixed, color: Colors.greenAccent),
                        title: Text('${driver['driver_name']} · ${driver['vehicle_plate']}',
                          style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${driver['availability_status']} · ${driver['active_ride_status'] ?? 'No active ride'} · ${(driver['latitude'] as num).toStringAsFixed(5)}, ${(driver['longitude'] as num).toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        trailing: updated == null ? null : Text(DateFormat('HH:mm:ss').format(updated.toLocal()),
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      );
                    }),
                  _sectionTitle('Team', _addMember, 'Add member'),
                  ..._members.map((member) => ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.white60),
                    title: Text(member['member_name']?.toString() ?? 'STA member', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${member['member_role']} · ${member['member_status']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: Text(member['phone_number']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  _sectionTitle('Branches', _addBranch, 'Add branch'),
                  if (_branches.isEmpty)
                    const Text('No branches registered.', style: TextStyle(color: Colors.white54))
                  else
                    ..._branches.map((branch) => ListTile(
                      leading: const Icon(Icons.location_city, color: Colors.white60),
                      title: Text(branch['name']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${branch['city'] ?? ''} · ${branch['region'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                    )),
                  _sectionTitle('Fuel logs', _logFuel, 'Log fuel'),
                  ..._fuelLogs.map((log) => ListTile(
                    leading: const Icon(Icons.local_gas_station, color: Colors.orangeAccent),
                    title: Text('${log['quantity_liters']} L · ${_currency(log['total_cost'])}', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${log['fuel_station'] ?? 'Fuel purchase'} · ${log['created_at']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  )),
                  _sectionTitle('Maintenance', _scheduleMaintenance, 'Schedule'),
                  ..._maintenance.map((record) => ListTile(
                    leading: Icon(record['status'] == 'completed' ? Icons.check_circle : Icons.build_circle,
                      color: record['status'] == 'completed' ? Colors.greenAccent : Colors.orangeAccent),
                    title: Text(record['maintenance_type']?.toString() ?? 'Maintenance', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${record['status']} · ${_currency(record['cost'])}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: ['scheduled','in_progress'].contains(record['status'])
                        ? IconButton(
                            tooltip: 'Mark completed',
                            icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                            onPressed: () async {
                              try {
                                await _db.rpc('sta_set_vehicle_maintenance_status', params: {
                                  'p_record_id': record['id'],
                                  'p_status': 'completed',
                                });
                                await _loadOrganizationData();
                              } catch (error) { _showMessage('Could not update maintenance: $error'); }
                            },
                          )
                        : null,
                  )),
                  _sectionTitle('Transport contracts', _addContract, 'Add contract'),
                  ..._contracts.map((contract) => ListTile(
                    leading: const Icon(Icons.description_outlined, color: Colors.white60),
                    title: Text(contract['client_name']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${contract['contract_reference'] ?? 'No reference'} · ${contract['status']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: contract['contract_value'] == null ? null : Text(_currency(contract['contract_value']), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  )),
                ],
              ),
            ),
    );
  }
}
