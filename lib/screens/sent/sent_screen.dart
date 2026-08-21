import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ig_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/request_card.dart';

class SentScreen extends StatelessWidget {
  const SentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);
    final user = authService.currentUser;
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hồ sơ đã gửi'),
          elevation: 0,
          bottom: TabBar(
            labelColor: theme.primaryColor,
            unselectedLabelColor: const Color(0xFF8E8E93),
            indicatorColor: theme.primaryColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
            tabs: const [
              Tab(text: 'Instagram'),
              Tab(text: 'Facebook'),
            ],
          ),
        ),
        body: StreamBuilder<List<IGRequestModel>>(
          stream: firestoreService.streamSentRequests(user?.uid ?? '', user?.pairId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Đã xảy ra lỗi khi tải dữ liệu.',
                  style: TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final sentList = snapshot.data ?? [];
            final instagramList = sentList.where((r) => r.accountType == 'instagram').toList();
            final facebookList = sentList.where((r) => r.accountType == 'facebook').toList();

            return TabBarView(
              children: [
                _RequestListWithFilter(list: instagramList, typeLabel: 'Instagram'),
                _RequestListWithFilter(list: facebookList, typeLabel: 'Facebook'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestListWithFilter extends StatefulWidget {
  final List<IGRequestModel> list;
  final String typeLabel;

  const _RequestListWithFilter({
    required this.list,
    required this.typeLabel,
  });

  @override
  State<_RequestListWithFilter> createState() => _RequestListWithFilterState();
}

class _RequestListWithFilterState extends State<_RequestListWithFilter> {
  String _filter = 'all'; // 'all', 'verified', 'dead'

  @override
  Widget build(BuildContext context) {
    List<IGRequestModel> filtered = widget.list;
    if (_filter == 'verified') {
      filtered = filtered.where((r) => r.isVerified).toList();
    } else if (_filter == 'dead') {
      filtered = filtered.where((r) => r.accountStatus == 'dead').toList();
    }

    final verifiedCount = widget.list.where((r) => r.isVerified).length;
    final deadCount = widget.list.where((r) => r.accountStatus == 'dead').length;

    if (widget.list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_outlined,
                size: 48,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa gửi hồ sơ ${widget.typeLabel} nào',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Các hồ sơ ${widget.typeLabel} bạn gửi cho người kia sẽ xuất hiện ở đây.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/create_ig_request');
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Gửi hồ sơ ngay'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 45),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Quick filter chips row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ChoiceChip(
                label: Text('Tất cả (${widget.list.length})'),
                selected: _filter == 'all',
                onSelected: (selected) {
                  if (selected) setState(() => _filter = 'all');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(Icons.verified, size: 16, color: Colors.blue),
                label: Text('Đã tích xanh ($verifiedCount)'),
                selected: _filter == 'verified',
                selectedColor: Colors.blue.shade50,
                onSelected: (selected) {
                  if (selected) setState(() => _filter = 'verified');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(Icons.heart_broken_outlined, size: 16, color: Colors.red),
                label: Text('Tài khoản DIE ($deadCount)'),
                selected: _filter == 'dead',
                selectedColor: Colors.red.shade50,
                onSelected: (selected) {
                  if (selected) setState(() => _filter = 'dead');
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _filter == 'verified'
                        ? 'Không có hồ sơ tích xanh nào'
                        : _filter == 'dead'
                            ? 'Không có tài khoản DIE nào'
                            : 'Danh sách trống',
                    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemBuilder: (context, index) {
                      final request = filtered[index];
                      return RequestCard(
                        request: request,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/ig_request_detail',
                            arguments: request,
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

