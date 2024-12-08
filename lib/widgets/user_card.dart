import 'package:flutter/material.dart';

class UserCard extends StatelessWidget {
  final String userId;
  final String? userName;
  final String? deviceName;

  const UserCard({
    super.key,
    required this.userId,
    this.userName,
    this.deviceName,
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
                      Text(
                        userName!,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                      Text(
                        deviceName!,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                /*
                Container(
                  width: 24,
                  decoration: BoxDecoration(
                      color:  Colors.green,
                      shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '7',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                */
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
