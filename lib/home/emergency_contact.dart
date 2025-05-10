import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class EmergencyContactsPage extends StatefulWidget {
  @override
  _EmergencyContactsPageState createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> contacts = [];
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();

  // Get current user
  User? get user => _auth.currentUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }

  // Load contacts from Firebase using UID as the key
  Future<void> _loadContacts() async {
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Reference directly to the user's emergency contacts
      final ref = _database.ref("emergency_contacts/${user!.uid}");
      final snapshot = await ref.get();

      List<Map<String, dynamic>> loadedContacts = [];

      if (snapshot.exists) {
        Map<dynamic, dynamic>? values = snapshot.value as Map?;
        if (values != null) {
          values.forEach((contactKey, contactValue) {
            if (contactValue is Map) {
              loadedContacts.add({
                'id': contactKey,
                'name': contactValue['name'] ?? '',
                'phone': contactValue['phone'] ?? '',
                'status_activate': contactValue['status_activate'] ?? true,
              });
            }
          });
        }
      }

      setState(() {
        contacts = loadedContacts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading contacts: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load contacts: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add a new contact using user UID as the key
  Future<void> _addContact() async {
    if (_formKey.currentState!.validate() && user != null) {
      try {
        setState(() {
          _isLoading = true;
        });

        // Reference directly to the user's emergency contacts node using UID
        DatabaseReference contactsRef = _database.ref(
          "emergency_contacts/${user!.uid}",
        );

        // Use push() to get a new unique key
        DatabaseReference newContactRef = contactsRef.push();

        // Get the key that push() created
        String? contactId = newContactRef.key;

        if (contactId == null) {
          throw Exception("Failed to generate a contact ID");
        }

        // Create the data to save
        Map<String, dynamic> contactData = {
          'name': nameController.text.trim(),
          'phone': numberController.text.trim(),
          'status_activate': true,
          'uid': user!.uid,
          'timestamp': ServerValue.timestamp,
        };

        // Set the data at the specific location
        await contactsRef.child(contactId).set(contactData);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency contact added successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        nameController.clear();
        numberController.clear();

        // Close the dialog
        Navigator.pop(context);

        // Reload contacts
        await _loadContacts();
      } catch (e) {
        print('Error adding contact: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add contact: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Delete a contact
  Future<void> _deleteContact(String contactId) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Delete directly using the UID structure
      await _database
          .ref("emergency_contacts/${user!.uid}/$contactId")
          .remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Reload contacts
      await _loadContacts();
    } catch (e) {
      print('Error deleting contact: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Build the contact form
  Widget _buildContactForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name *',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: numberController,
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a phone number';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Contacts',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
        backgroundColor: Colors.red,
      ),

      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : user == null
              ? Center(child: Text('Please log in to view emergency contacts'))
              : contacts.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.contact_phone,
                      size: 60,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No emergency contacts added yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the + button to add a contact',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 2,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red[100],
                        child: const Icon(Icons.person, color: Colors.red),
                      ),
                      title: Text(
                        contact['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.phone, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(contact['phone']),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Delete Contact'),
                                  content: Text(
                                    'Are you sure you want to delete ${contact['name']} from your emergency contacts?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('CANCEL'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        _deleteContact(contact['id']);
                                        Navigator.pop(context);
                                      },
                                      child: const Text(
                                        'DELETE',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton:
          user == null || _isLoading
              ? null
              : FloatingActionButton(
                onPressed: () {
                  nameController.clear();
                  numberController.clear();
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Text(
                            'Add Emergency Contact',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          content: SingleChildScrollView(
                            child: _buildContactForm(),
                          ),
                          actionsPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          actionsAlignment: MainAxisAlignment.end,
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              child: const Text('CANCEL'),
                            ),
                            ElevatedButton(
                              onPressed: _addContact,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              child: const Text('ADD'),
                            ),
                          ],
                        ),
                  );
                },
                backgroundColor: Colors.red,
                child: const Icon(Icons.add, color: Colors.white),
              ),
    );
  }
}
