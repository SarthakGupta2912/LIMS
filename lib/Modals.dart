// Product model class
class Product {
  final String name;
  final String id;
  final double price;

  Product({required this.name, required this.id, required this.price});

  // Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {'name': name, 'id': id, 'price': price};
  }

  // Create from Map
  static Product fromMap(Map<String, dynamic> map) {
    return Product(name: map['name'], id: map['id'], price: map['price']);
  }
}
