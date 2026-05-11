import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/medication.dart';
import '../theme/app_theme.dart';
import '../utils/watchlist_actions.dart';
import 'medication_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(
        () => _showHistory =
            _focusNode.hasFocus && _searchController.text.isEmpty,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Extract unique categories from medications
    final categories = ['All'];
    final uniqueCats = appState.medications
        .map((m) => m.category)
        .toSet()
        .toList();
    categories.addAll(uniqueCats);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedTrack360'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showSortOptions(context, appState),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search by brand, generic name, or category...',
                hintStyle: const TextStyle(color: MedTrackColors.textHint),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          appState.setSearchQuery('');
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: MedTrackColors.surfaceAlt,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                appState.setSearchQuery(value);
                setState(
                  () => _showHistory = value.isEmpty && _focusNode.hasFocus,
                );
              },
              onSubmitted: (value) {
                appState.commitSearch(value);
                _focusNode.unfocus();
                setState(() => _showHistory = false);
              },
            ),
          ),

          // Category chips
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = appState.selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => appState.setCategory(cat),
                    selectedColor: MedTrackColors.primary.withValues(
                      alpha: 0.15,
                    ),
                    checkmarkColor: MedTrackColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? MedTrackColors.primary
                          : MedTrackColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),

          // Content
          Expanded(
            child: _showHistory
                ? _buildSearchHistory(appState)
                : _buildMedicationList(appState),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHistory(AppState appState) {
    if (appState.searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: MedTrackColors.divider),
            const SizedBox(height: 12),
            const Text(
              'No search history yet',
              style: TextStyle(color: MedTrackColors.textHint, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MedTrackColors.textSecondary,
                ),
              ),
              TextButton(
                onPressed: () => appState.clearSearchHistory(),
                child: const Text('Clear All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: appState.searchHistory.length,
            itemBuilder: (context, index) {
              final item = appState.searchHistory[index];
              return ListTile(
                leading: const Icon(Icons.history, color: Colors.grey),
                title: Text(item.query),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => appState.removeFromSearchHistory(item.query),
                ),
                onTap: () {
                  _searchController.text = item.query;
                  appState.setSearchQuery(item.query);
                  _focusNode.unfocus();
                  setState(() => _showHistory = false);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationList(AppState appState) {
    final medications = appState.filteredMedications;

    if (medications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 80,
              color: MedTrackColors.divider,
            ),
            const SizedBox(height: 16),
            const Text(
              'No medications found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: MedTrackColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting your search or filters',
              style: TextStyle(color: MedTrackColors.textHint),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: medications.length,
      itemBuilder: (context, index) {
        return _MedicationCard(medication: medications[index]);
      },
    );
  }

  void _showSortOptions(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sort Results',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildSortOption(
                  context,
                  appState,
                  'name',
                  'Name (A-Z)',
                  Icons.sort_by_alpha,
                ),
                _buildSortOption(
                  context,
                  appState,
                  'proximity',
                  'Nearest Pharmacy',
                  Icons.near_me,
                ),
                _buildSortOption(
                  context,
                  appState,
                  'rating',
                  'Highest Rated',
                  Icons.star,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSortOption(
    BuildContext context,
    AppState appState,
    String value,
    String label,
    IconData icon,
  ) {
    final isSelected = appState.sortBy == value;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        appState.setSortBy(value);
        Navigator.pop(context);
      },
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final Medication medication;

  const _MedicationCard({required this.medication});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final inWatchlist = appState.isInWatchlist(medication.key);
    final availabilityColor = _getAvailabilityColor(
      medication.mophCeiling / 100,
    );
    final pharmaciesWithStock = appState.getPharmaciesWithMedication(
      medication.key,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Treat opening a result as "the user found what they typed" —
          // commit the current query to history so we store full words
          // (e.g. "panadol") instead of every keystroke prefix.
          appState.commitSearch(appState.searchQuery);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MedicationDetailScreen(medication: medication),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Medication icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getMedicationIcon(medication.form),
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medication.tradeName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${medication.genericName} · ${medication.dosage}',
                          style: const TextStyle(
                            color: MedTrackColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                      color: inWatchlist
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    onPressed: () => toggleWatchlist(context, medication),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Category & form
              Row(
                children: [
                  _Chip(
                    label: medication.category,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _Chip(label: medication.form, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              // Bottom row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Price
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        size: 18,
                        color: MedTrackColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '\$${medication.mophCeiling.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: MedTrackColors.success,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Ministry Price',
                        style: TextStyle(
                          fontSize: 12,
                          color: MedTrackColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  // Availability
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: availabilityColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(medication.mophCeiling / 100 * 100).toInt()}% Available',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (pharmaciesWithStock.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '📍 Available at ${pharmaciesWithStock.length} nearby ${pharmaciesWithStock.length == 1 ? 'pharmacy' : 'pharmacies'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MedTrackColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getAvailabilityColor(double score) {
    if (score >= 0.8) return MedTrackColors.success;
    if (score >= 0.5) return MedTrackColors.warning;
    return MedTrackColors.error;
  }

  IconData _getMedicationIcon(String form) {
    switch (form.toLowerCase()) {
      case 'tablet':
        return Icons.medication;
      case 'capsule':
        return Icons.medication_liquid;
      case 'inhaler':
        return Icons.air;
      case 'syrup':
        return Icons.local_drink;
      default:
        return Icons.medication;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MedTrackColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: MedTrackColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
