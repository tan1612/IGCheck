import 'package:flutter/material.dart';
import '../../models/ig_request_model.dart';
import '../../widgets/request_card.dart';

class FilteredRequestsScreen extends StatelessWidget {
  final String title;
  final List<IGRequestModel> requests;

  const FilteredRequestsScreen({
    super.key,
    required this.title,
    required this.requests,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title),
      ),
      body: requests.isEmpty
          ? const Center(
              child: Text(
                'Không có hồ sơ nào.',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
            )
          : ListView.builder(
              itemCount: requests.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final request = requests[index];
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
    );
  }
}
