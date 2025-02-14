import 'package:flutter/material.dart';

class UserCard extends StatelessWidget {
  final String userId;
  final String? userName;
  final String? deviceName;
  final int unreadMessages;
  final bool isIndirect;
  final bool isUnderVerification;

  const UserCard({
    super.key,
    required this.userId,
    this.userName,
    this.deviceName,
    this.unreadMessages = 0,
    this.isIndirect = false,
    this.isUnderVerification = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Image(
                  image: AssetImage('assets/user_image.png'),
                  width: 64,
                  color: Colors.white,
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            userName ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          if (isIndirect) ...[
                            SizedBox(
                              width: 6,
                            ),
                            Icon(
                              Icons.airline_stops,
                              color: Colors.blueAccent,
                            ),
                          ]
                        ],
                      ),
                      Text(
                        deviceName ?? 'Unknown device',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                if (isUnderVerification)
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orangeAccent,
                  ),
                SizedBox(
                  width: 6,
                ),
                if (unreadMessages > 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$unreadMessages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(
          height: 8,
        ),
      ],
    );
  }
}
