import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/prediction_provider.dart';
import '../providers/wallet_provider.dart';

class PredictionMarketScreen extends ConsumerStatefulWidget {
  const PredictionMarketScreen({super.key});

  @override
  ConsumerState<PredictionMarketScreen> createState() => _PredictionMarketScreenState();
}

class _PredictionMarketScreenState extends ConsumerState<PredictionMarketScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showBetSlip(Map<String, dynamic> prediction, String matchName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BetSlipBottomSheet(
        prediction: prediction,
        matchName: matchName,
        currentBalance: ref.read(walletBalanceProvider),
        onPlaceBet: (amount) async {
          try {
            await ref.read(predictionServiceProvider).placeBet(
              prediction['id'],
              amount,
              (amount * prediction['odds']).toInt(),
            );
            
            // Refresh bets
            ref.invalidate(myBetsProvider);
            
            if (!mounted) return;
            setState(() {
              _tabController.animateTo(1); // switch to my bets
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Prediction locked in! Good luck! 🎯'),
                backgroundColor: context.colors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to place bet: ${e.toString()}'),
                backgroundColor: context.colors.error,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final virtualCurrency = ref.watch(walletBalanceProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.colors.textHigh, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'PREDICTIONS',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.colors.accent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.monetization_on, color: context.colors.accent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$virtualCurrency',
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.colors.accent,
          indicatorWeight: 3,
          labelColor: context.colors.textHigh,
          unselectedLabelColor: context.colors.textMedium,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
          tabs: const [
            Tab(text: 'LIVE MARKETS'),
            Tab(text: 'MY BETS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveMarkets(),
          _buildMyBets(),
        ],
      ),
    );
  }

  Widget _buildLiveMarkets() {
    final activeMarketsAsync = ref.watch(activeMarketsProvider);
    
    return activeMarketsAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
      error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: context.colors.error))),
      data: (predictions) {
        if (predictions.isEmpty) {
          return Center(
            child: Text('No active markets right now.', style: TextStyle(color: context.colors.textMedium)),
          );
        }

        // Group predictions by match
        Map<String, Map<String, dynamic>> groupedMatches = {};
        for (var pred in predictions) {
          final matchId = pred['match_id'];
          final match = pred['matches'];
          if (match == null) continue;

          if (!groupedMatches.containsKey(matchId)) {
            groupedMatches[matchId] = {
              'id': matchId,
              'match': '${match['home_team']} vs ${match['away_team']}',
              'status': match['status'] == 'live' ? 'LIVE ${match['minute'] ?? ''}' : match['status'].toString().toUpperCase(),
              'score': '${match['home_score']} - ${match['away_score']}',
              'predictions': <Map<String, dynamic>>[],
            };
          }
          
          groupedMatches[matchId]!['predictions'].add({
            'id': pred['id'],
            'title': pred['prediction_type'],
            'odds': (pred['odds'] as num).toDouble(),
          });
        }

        final marketsList = groupedMatches.values.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: marketsList.length,
          itemBuilder: (context, index) {
            final market = marketsList[index];
            final isLive = market['status'].toString().contains('LIVE');
            
            return Container(
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
                border: Border.all(color: context.colors.outline.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Match Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceVariant.withOpacity(0.5),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                market['match'],
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textHigh,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (isLive)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: context.colors.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  if (isLive) const SizedBox(width: 6),
                                  Text(
                                    market['status'],
                                    style: TextStyle(
                                      color: isLive ? context.colors.error : context.colors.textMedium,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.outline.withOpacity(0.3)),
                          ),
                          child: Text(
                            market['score'],
                            style: TextStyle(
                              color: context.colors.textHigh,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Predictions List
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: (market['predictions'] as List).map((pred) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _showBetSlip(pred, market['match']),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.colors.outline.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      pred['title'],
                                      style: TextStyle(
                                        color: context.colors.textHigh,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: context.colors.accent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      pred['odds'].toStringAsFixed(2),
                                      style: TextStyle(
                                        color: context.colors.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }

  Widget _buildMyBets() {
    final myBetsAsync = ref.watch(myBetsProvider);

    return myBetsAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
      error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: context.colors.error))),
      data: (bets) {
        if (bets.isEmpty) {
          return Center(
            child: Text('You have not placed any bets yet.', style: TextStyle(color: context.colors.textMedium)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bets.length,
          itemBuilder: (context, index) {
            final bet = bets[index];
            final isPending = bet['status'] == 'pending';
            final isWon = bet['status'] == 'won';
            
            Color statusColor = context.colors.textMedium;
            IconData statusIcon = Icons.access_time;
            if (isWon) {
              statusColor = context.colors.success;
              statusIcon = Icons.check_circle;
            } else if (bet['status'] == 'lost') {
              statusColor = context.colors.error;
              statusIcon = Icons.cancel;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.outline.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        bet['match'],
                        style: TextStyle(color: context.colors.textMedium, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            bet['status'].toUpperCase(),
                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bet['prediction'],
                    style: TextStyle(color: context.colors.textHigh, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('STAKE', style: TextStyle(color: context.colors.textMedium, fontSize: 10, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.monetization_on, color: context.colors.textHigh, size: 14),
                              const SizedBox(width: 4),
                              Text('${bet['staked']}', style: TextStyle(color: context.colors.textHigh, fontSize: 14, fontWeight: FontWeight.w800)),
                            ],
                          )
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('TO RETURN', style: TextStyle(color: context.colors.textMedium, fontSize: 10, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.monetization_on, color: isWon ? context.colors.success : (isPending ? context.colors.accent : context.colors.textMedium), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${bet['potentialPayout']}', 
                                style: TextStyle(
                                  color: isWon ? context.colors.success : (isPending ? context.colors.accent : context.colors.textMedium), 
                                  fontSize: 14, 
                                  fontWeight: FontWeight.w800
                                )
                              ),
                            ],
                          )
                        ],
                      )
                    ],
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }
}

class BetSlipBottomSheet extends StatefulWidget {
  final Map<String, dynamic> prediction;
  final String matchName;
  final int currentBalance;
  final Function(int) onPlaceBet;

  const BetSlipBottomSheet({
    super.key,
    required this.prediction,
    required this.matchName,
    required this.currentBalance,
    required this.onPlaceBet,
  });

  @override
  State<BetSlipBottomSheet> createState() => _BetSlipBottomSheetState();
}

class _BetSlipBottomSheetState extends State<BetSlipBottomSheet> {
  int _stake = 100;
  final TextEditingController _controller = TextEditingController(text: '100');

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final val = int.tryParse(_controller.text) ?? 0;
      setState(() {
        _stake = val;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setStake(int amount) {
    if (amount > widget.currentBalance) {
      amount = widget.currentBalance;
    }
    setState(() {
      _stake = amount;
      _controller.text = amount.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final potentialReturn = (_stake * widget.prediction['odds']).toInt();
    final isValid = _stake > 0 && _stake <= widget.currentBalance;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.outline.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'PLACE PREDICTION',
                style: TextStyle(color: context.colors.textMedium, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Bet details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.colors.outline.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.matchName,
                      style: TextStyle(color: context.colors.textMedium, fontSize: 12, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.prediction['title'],
                      style: TextStyle(color: context.colors.textHigh, fontSize: 18, fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'ODDS ${widget.prediction['odds'].toStringAsFixed(2)}',
                        style: TextStyle(color: context.colors.accent, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Quick stakes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickStakeBtn(50),
                  _buildQuickStakeBtn(100),
                  _buildQuickStakeBtn(500),
                  _buildQuickStakeBtn(widget.currentBalance, label: 'MAX'),
                ],
              ),
              const SizedBox(height: 16),

              // Custom amount input
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isValid ? context.colors.outline : context.colors.error, width: 2),
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Icon(Icons.monetization_on, color: context.colors.textMedium, size: 20),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: TextStyle(color: context.colors.textHigh, fontSize: 18, fontWeight: FontWeight.w800),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                hintText: 'Stake Amount',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('EST. RETURN', style: TextStyle(color: context.colors.textMedium, fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        '$potentialReturn',
                        style: TextStyle(color: context.colors.success, fontSize: 24, fontWeight: FontWeight.w900),
                      )
                    ],
                  )
                ],
              ),
              if (!isValid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Insufficient balance.',
                    style: TextStyle(color: context.colors.error, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              
              const SizedBox(height: 32),
              
              // Place Bet Button
              ElevatedButton(
                onPressed: isValid ? () {
                  Navigator.pop(context);
                  widget.onPlaceBet(_stake);
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: context.colors.background,
                  disabledBackgroundColor: context.colors.surfaceVariant,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text(
                  'PLACE PREDICTION',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStakeBtn(int amount, {String? label}) {
    return InkWell(
      onTap: () => _setStake(amount),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.outline.withOpacity(0.3)),
        ),
        child: Text(
          label ?? '+$amount',
          style: TextStyle(color: context.colors.textHigh, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

