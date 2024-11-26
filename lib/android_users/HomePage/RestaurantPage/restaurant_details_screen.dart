import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'restaurant_data_manager.dart';

class RestaurantDetailsScreen extends StatefulWidget {
  final String restaurantId;

  const RestaurantDetailsScreen({Key? key, required this.restaurantId}) : super(key: key);

  @override
  _RestaurantDetailsScreenState createState() => _RestaurantDetailsScreenState();
}

class _RestaurantDetailsScreenState extends State<RestaurantDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RestaurantDataManager _restaurantDataManager = RestaurantDataManager();

  Map<String, dynamic>? _restaurant;
  List<Map<String, dynamic>> _menuItems = [];
  Map<String, Map<String, dynamic>> _cartItems = {};
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _guestCount = 1;
  String _paymentMethod = 'GCash';
  String _referenceNumber = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRestaurantData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRestaurantData() async {
    try {
      final restaurantData = await _restaurantDataManager.getRestaurantById(widget.restaurantId);
      if (restaurantData != null) {
        setState(() {
          _restaurant = restaurantData;
          _menuItems = List<Map<String, dynamic>>.from(restaurantData['menuItems'] ?? []);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load restaurant data')),
        );
      }
    } catch (e) {
      print('Error loading restaurant data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred while loading restaurant data')),
      );
    }
  }

  void _addToCart(Map<String, dynamic> item) {
    setState(() {
      if (_cartItems.containsKey(item['name'])) {
        _cartItems[item['name']]!['quantity'] = (_cartItems[item['name']]!['quantity'] ?? 0) + 1;
      } else {
        _cartItems[item['name']] = {
          ...item,
          'quantity': 1,
        };
      }
    });
  }

  void _removeFromCart(String itemName) {
    setState(() {
      if (_cartItems.containsKey(itemName)) {
        if (_cartItems[itemName]!['quantity'] > 1) {
          _cartItems[itemName]!['quantity'] = _cartItems[itemName]!['quantity'] - 1;
        } else {
          _cartItems.remove(itemName);
        }
      }
    });
  }

  void _deleteFromCart(String itemName) {
    setState(() {
      _cartItems.remove(itemName);
    });
  }

  double _calculateTotalPrice() {
    double total = 0;
    _cartItems.forEach((itemName, itemData) {
      total += (itemData['price'] as num) * (itemData['quantity'] as num);
    });
    return total;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 30)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      final now = DateTime.now();

      final selectedDateTime = DateTime(
        _selectedDate?.year ?? now.year,
        _selectedDate?.month ?? now.month,
        _selectedDate?.day ?? now.day,
        picked.hour,
        picked.minute,
      );

      if (selectedDateTime.isAfter(now)) {
        setState(() {
          _selectedTime = picked;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a future time')),
        );
      }
    }
  }

  bool _validateBooking() {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a date')),
      );
      return false;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a time')),
      );
      return false;
    }
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add items to your cart')),
      );
      return false;
    }
    if (_paymentMethod == 'GCash') {
      if (_referenceNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter the GCash reference number')),
        );
        return false;
      }
      if (!RegExp(r'^\d+$').hasMatch(_referenceNumber)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GCash reference number should only contain digits')),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _bookTable() async {
    if (!_validateBooking()) return;

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      final reservationData = {
        'userId': user.uid,
        'userEmail': user.email,
        'restaurantName': _restaurant?['name'] ?? '',
        'logoUrl': _restaurant?['logoUrl'] ?? '',
        'reservationDateTime': DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute),
        'status': 'pending',
        'items': _cartItems.values.toList(),
        'guestCount': _guestCount,
        'totalPrice': _calculateTotalPrice(),
        'paymentMethod': _paymentMethod,
        'referenceNumber': _referenceNumber,
      };

      await _restaurantDataManager.addReservation(widget.restaurantId, reservationData);

      Fluttertoast.showToast(
        msg: 'Reservation successful!',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.green,
        textColor: Colors.white,
        fontSize: 16.0,
      );

      setState(() {
        _guestCount = 1;
        _paymentMethod = 'GCash';
        _referenceNumber = '';
        _selectedDate = null;
        _selectedTime = null;
        _cartItems.clear();
      });

      Navigator.pop(context);
    } catch (e) {
      print('Error booking table: $e');
      Fluttertoast.showToast(
        msg: 'Failed to make reservation. Please try again.',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restaurant == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                _restaurant!['logoUrl'] ?? 'https://via.placeholder.com/400',
                fit: BoxFit.cover,
              ),
              title: Text(
                _restaurant!['name'] ?? 'Restaurant',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildLocationInfo(),
                TabBar(
                  controller: _tabController,
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: 'Menu'),
                    Tab(text: 'About'),
                  ],
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMenuContent(),
                      _buildAboutContent(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildLocationInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(Icons.location_on, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _restaurant?['address'] ?? 'Address not available',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuContent() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return _buildMenuItem(item);
      },
    );
  }

  Widget _buildMenuItem(Map<String, dynamic> item) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item['image'] ?? 'https://via.placeholder.com/100',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Unnamed Item',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    item['description'] ?? 'No description available',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'PHP ${(item['price'] as num).toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepOrange,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle, color: Colors.deepOrange),
              onPressed: () => _addToCart(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About ${_restaurant?['name']}',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _restaurant?['about'] ?? 'No information available',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Opening Hours',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _restaurant?['openingHours'] ?? 'Opening hours not available',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total: PHP ${_calculateTotalPrice().toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          ElevatedButton(
            onPressed: _showBookingModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange
              ,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Book a Table',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Book a Table',
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await _selectDate(context);
                              setModalState(() {});
                            },
                            child: Text(
                              _selectedDate == null
                                  ? 'Select Date'
                                  : DateFormat('MM/dd/yy').format(_selectedDate!),
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              side: BorderSide(color: Colors.deepOrange),
                            ),
                          ),
                        ),
                        SizedBox(width: 20),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await _selectTime(context);
                              setModalState(() {});
                            },
                            child: Text(
                              _selectedTime == null
                                  ? 'Select Time'
                                  : _selectedTime!.format(context),
                              style: TextStyle(color: Colors.deepOrange),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              side: BorderSide(color: Colors.deepOrange),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Number of Guests:',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.remove, color: Colors.deepOrange),
                          onPressed: () {
                            if (_guestCount > 1) {
                              setModalState(() => _guestCount--);
                            }
                          },
                        ),
                        Text(
                          _guestCount.toString(),
                          style: GoogleFonts.poppins(fontSize: 20),
                        ),
                        IconButton(
                          icon: Icon(Icons.add, color: Colors.deepOrange),
                          onPressed: () {
                            setModalState(() => _guestCount++);
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Order Summary',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Column(
                      children: _cartItems.entries.map((entry) {
                        final item = entry.value;
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 8),
                          elevation: 2,
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item['image'] ?? 'https://via.placeholder.com/50',
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            ),
                            title: Text(
                              item['name'],
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                            subtitle: Text(
                              'PHP ${(item['price'] as num).toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.deepOrange,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove, color: Colors.deepOrange),
                                  onPressed: () => setModalState(() => _removeFromCart(item['name'])),
                                ),
                                Text(
                                  item['quantity'].toString(),
                                  style: GoogleFonts.poppins(fontSize: 16),
                                ),
                                IconButton(
                                  icon: Icon(Icons.add, color: Colors.deepOrange),
                                  onPressed: () => setModalState(() => _addToCart(item)),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => setModalState(() => _deleteFromCart(item['name'])),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total:',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'PHP ${_calculateTotalPrice().toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Payment Method:',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    RadioListTile<String>(
                      title: Row(
                        children: [
                          Image.asset(
                            'lib/assets/app_images/gcash-logo.png',
                            width: 24,
                            height: 24,
                          ),
                          SizedBox(width: 8),
                          Text('GCash'),
                        ],
                      ),
                      value: 'GCash',
                      groupValue: _paymentMethod,
                      onChanged: (String? value) {
                        setModalState(() {
                          _paymentMethod = value!;
                        });
                      },
                    ),
                    if (_paymentMethod == 'GCash')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send payment to:',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _restaurant?['phoneNumber'] ?? 'GCash number not available',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepOrange,
                            ),
                          ),
                          SizedBox(height: 10),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'GCash Reference Number',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide(color: Colors.deepOrange),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setModalState(() {
                                _referenceNumber = value;
                              });
                            },
                          ),
                        ],
                      ),
                    SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _bookTable();
                          Navigator.pop(context);
                        },
                        child: Text(
                          'Confirm Booking',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

