import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

const String seedOrderJson =
    '[{"Item":"A1000","ItemName":"Iphone 15","Price":1200,"Currency":"USD","Quantity":1},'
    '{"Item":"A1001","ItemName":"Iphone 16","Price":1500,"Currency":"USD","Quantity":1}]';

final List<Order> _orders = <Order>[];
List<Order> _filteredOrders = <Order>[];

late web.HTMLInputElement _itemInput;
late web.HTMLInputElement _itemNameInput;
late web.HTMLInputElement _priceInput;
late web.HTMLInputElement _quantityInput;
late web.HTMLInputElement _currencyInput;
late web.HTMLInputElement _searchInput;
late web.HTMLButtonElement _addButton;
late web.HTMLTableSectionElement _ordersBody;
late web.HTMLParagraphElement _statusMessage;
late web.HTMLButtonElement _prevPageButton;
late web.HTMLButtonElement _nextPageButton;
late web.HTMLSpanElement _pageInfo;

const int _pageSize = 10;
int _currentPage = 1;

void main() {
  _bindDom();
  _loadInitialOrders();

  _addButton.onclick = ((web.Event _) {
    _handleAddOrder();
  }).toJS;
  _searchInput.oninput = ((web.Event _) {
    _applyFilter(resetPage: true);
  }).toJS;
  _prevPageButton.onclick = ((web.Event _) {
    _goToPreviousPage();
  }).toJS;
  _nextPageButton.onclick = ((web.Event _) {
    _goToNextPage();
  }).toJS;

  _render();
}

class Order {
  Order({
    required this.id,
    required this.item,
    required this.itemName,
    required this.price,
    required this.currency,
    required this.quantity,
  });

  final int id;
  final String item;
  final String itemName;
  final double price;
  final String currency;
  final int quantity;

  factory Order.fromJson(Map<String, dynamic> json, int id) {
    return Order(
      id: id,
      item: (json['Item'] ?? '').toString().trim(),
      itemName: (json['ItemName'] ?? '').toString().trim(),
      price: _toDouble(json['Price']),
      currency: (json['Currency'] ?? '').toString().trim(),
      quantity: _toInt(json['Quantity']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Item': item,
      'ItemName': itemName,
      'Price': price,
      'Currency': currency,
      'Quantity': quantity,
    };
  }
}

void _bindDom() {
  _itemInput = web.document.querySelector('#itemInput') as web.HTMLInputElement;
  _itemNameInput =
      web.document.querySelector('#itemNameInput') as web.HTMLInputElement;
  _priceInput = web.document.querySelector('#priceInput') as web.HTMLInputElement;
  _quantityInput =
      web.document.querySelector('#quantityInput') as web.HTMLInputElement;
  _currencyInput =
      web.document.querySelector('#currencyInput') as web.HTMLInputElement;
  _searchInput =
      web.document.querySelector('#searchInput') as web.HTMLInputElement;
  _addButton = web.document.querySelector('#addButton') as web.HTMLButtonElement;
  _ordersBody =
      web.document.querySelector('#ordersBody') as web.HTMLTableSectionElement;
  _statusMessage =
      web.document.querySelector('#statusMessage') as web.HTMLParagraphElement;
    _prevPageButton =
      web.document.querySelector('#prevPageButton') as web.HTMLButtonElement;
    _nextPageButton =
      web.document.querySelector('#nextPageButton') as web.HTMLButtonElement;
    _pageInfo = web.document.querySelector('#pageInfo') as web.HTMLSpanElement;
}

void _loadInitialOrders() {
  try {
    final dynamic decoded = jsonDecode(seedOrderJson);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Order JSON must be a list.');
    }

    _orders
      ..clear()
      ..addAll(
        decoded.asMap().entries.map((MapEntry<int, dynamic> entry) {
          final dynamic row = entry.value;
          if (row is! Map<String, dynamic>) {
            throw const FormatException('Each order must be an object.');
          }
          return Order.fromJson(row, entry.key + 1);
        }),
      );

    _filteredOrders = List<Order>.from(_orders);
    _currentPage = 1;
    _setStatus('Loaded ${_orders.length} orders from JSON.', isError: false);
  } on Object catch (error) {
    _orders.clear();
    _filteredOrders = <Order>[];
    _currentPage = 1;
    _setStatus('Could not parse initial JSON: $error', isError: true);
  }
}

void _handleAddOrder() {
  final String item = _itemInput.value.trim();
  final String itemName = _itemNameInput.value.trim();
  final String currency = _currencyInput.value.trim().toUpperCase();
  final double? price = double.tryParse(_priceInput.value.trim());
  final int? quantity = int.tryParse(_quantityInput.value.trim());

  if (item.isEmpty || itemName.isEmpty || currency.isEmpty) {
    _setStatus('Item, Item Name, and Currency are required.', isError: true);
    return;
  }

  if (price == null || price <= 0) {
    _setStatus('Price must be a positive number.', isError: true);
    return;
  }

  if (quantity == null || quantity <= 0) {
    _setStatus('Quantity must be a positive integer.', isError: true);
    return;
  }

  final Order newOrder = Order(
    id: _orders.isEmpty ? 1 : _orders.last.id + 1,
    item: item,
    itemName: itemName,
    price: price,
    currency: currency,
    quantity: quantity,
  );

  _orders.add(newOrder);
  _applyFilter();
  _currentPage = _totalPages;
  _render();

  final String updatedJson =
      jsonEncode(_orders.map((Order e) => e.toJson()).toList());

  _itemInput.value = '';
  _itemNameInput.value = '';
  _priceInput.value = '';
  _quantityInput.value = '';

  _setStatus(
    'Order inserted. Total orders in order.json: ${_orders.length} (${updatedJson.length} chars).',
    isError: false,
  );
}

void _applyFilter({bool resetPage = false}) {
  final String keyword = _searchInput.value.trim().toLowerCase();
  if (keyword.isEmpty) {
    _filteredOrders = List<Order>.from(_orders);
  } else {
    _filteredOrders = _orders
        .where(
          (Order order) => order.itemName.toLowerCase().contains(keyword),
        )
        .toList();
  }

  if (resetPage) {
    _currentPage = 1;
  }
  _clampCurrentPage();
  _render();
}

void _render() {
  _renderOrders();
  _renderPagination();
}

void _renderOrders() {
  while (_ordersBody.firstChild != null) {
    _ordersBody.removeChild(_ordersBody.firstChild!);
  }

  if (_filteredOrders.isEmpty) {
    final web.HTMLTableRowElement emptyRow =
        web.document.createElement('tr') as web.HTMLTableRowElement;
    final web.HTMLTableCellElement emptyCell =
        web.document.createElement('td') as web.HTMLTableCellElement;
    emptyCell
      ..setAttribute('colspan', '7')
      ..className = 'empty'
      ..textContent = 'No matching orders.';
    emptyRow.append(emptyCell);
    _ordersBody.append(emptyRow);
    return;
  }

  final int start = (_currentPage - 1) * _pageSize;
  final int endExclusive = min(start + _pageSize, _filteredOrders.length);
  final List<Order> pageItems = _filteredOrders.sublist(start, endExclusive);

  for (final Order order in pageItems) {
    final web.HTMLTableRowElement row =
        web.document.createElement('tr') as web.HTMLTableRowElement;

    row.append(_textCell(order.id.toString()));
    row.append(_textCell(order.item));
    row.append(_textCell(order.itemName));
    row.append(_textCell(order.quantity.toString()));
    row.append(_textCell(_formatPrice(order.price)));
    row.append(_textCell(order.currency));
    row.append(_deleteCell(order));

    _ordersBody.append(row);
  }
}

void _renderPagination() {
  _pageInfo.textContent = 'Page $_currentPage / $_totalPages';
  _prevPageButton.disabled = _currentPage <= 1;
  _nextPageButton.disabled = _currentPage >= _totalPages;
}

void _goToPreviousPage() {
  if (_currentPage <= 1) {
    return;
  }
  _currentPage--;
  _render();
}

void _goToNextPage() {
  if (_currentPage >= _totalPages) {
    return;
  }
  _currentPage++;
  _render();
}

web.HTMLTableCellElement _deleteCell(Order order) {
  final web.HTMLTableCellElement cell =
      web.document.createElement('td') as web.HTMLTableCellElement;
  final web.HTMLButtonElement button =
      web.document.createElement('button') as web.HTMLButtonElement;
  button
    ..className = 'delete-btn'
    ..textContent = 'Delete'
    ..type = 'button'
    ..onclick = ((web.Event _) {
      _deleteOrder(order.id);
    }).toJS;
  cell.append(button);
  return cell;
}

void _deleteOrder(int id) {
  _orders.removeWhere((Order order) => order.id == id);
  _applyFilter();
  _setStatus('Order $id deleted. Remaining: ${_orders.length}.', isError: false);
}

void _clampCurrentPage() {
  if (_currentPage < 1) {
    _currentPage = 1;
  }
  if (_currentPage > _totalPages) {
    _currentPage = _totalPages;
  }
}

int get _totalPages {
  if (_filteredOrders.isEmpty) {
    return 1;
  }
  return (_filteredOrders.length / _pageSize).ceil();
}

web.HTMLTableCellElement _textCell(String value) {
  final web.HTMLTableCellElement cell =
      web.document.createElement('td') as web.HTMLTableCellElement;
  cell.textContent = value;
  return cell;
}

void _setStatus(String message, {required bool isError}) {
  _statusMessage
    ..textContent = message
    ..className = 'status ${isError ? 'error' : 'success'}';
}

String _formatPrice(double value) {
  if (value % 1 == 0) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

double _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString()) ?? 0;
}
