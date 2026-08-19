import 'dart:convert';
import 'company_store.dart';

/// ⭐ Guest Preview Mode — bharpoor demo data. Sirf local SharedPreferences
/// mein save hota hai, CompanyStore khud companyId null dekh ke Firestore
/// ko kabhi touch nahi karega.
class DemoDataService {
  DemoDataService._();

  static String _ddmmyyyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _iso(DateTime d) => d.toIso8601String();

  static Future<void> seedDemoData() async {
    final now = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 1️⃣ FARMERS + BATCHES (with daily entries)
    // ═══════════════════════════════════════════════════════════
    final batch1Start = now.subtract(const Duration(days: 18));
    final batch2Start = now.subtract(const Duration(days: 32));
    final batch3Start = now.subtract(const Duration(days: 55));
    final batch3End = now.subtract(const Duration(days: 5));

    final demoFarmers = [
      {
        'id': 'demo_farmer_1',
        'name': 'Ramesh Kumar (Demo)',
        'phone': '9999900001',
        'district': 'Patna',
        'state': 'Bihar',
        'status': 'active',
        'dob': '15/06/1985',
        'aadhaar': '999900001111',
        'bankName': 'SBI',
        'accountHolder': 'Ramesh Kumar',
        'accountNumber': '99990000111122',
        'ifsc': 'SBIN0001234',
        'batches': [
          {
            'id': 'demo_batch_1',
            'batchId': 'demo_batch_1',
            'status': 'ACTIVE',
            'chicksCount': 5000,
            'chicksRate': 40.0,
            'totalChicksCost': '200000.00',
            'startDate': _ddmmyyyy(batch1Start),
            'dailyEntries': [
              {
                'type': 'cost',
                'entryId': 'demo_e1',
                'date': _ddmmyyyy(batch1Start.add(const Duration(days: 5))),
                'transactionDate': _ddmmyyyy(
                  batch1Start.add(const Duration(days: 5)),
                ),
                'createdAt': _iso(batch1Start.add(const Duration(days: 5))),
                'weight': '0.35',
                'mortality': '8',
                'feed': '20',
                'feedStarterBags': 20,
                'feedGrowerBags': 0,
                'feedFinisherBags': 0,
                'feedStarterKgPerBag': 50.0,
                'feedGrowerKgPerBag': 50.0,
                'feedFinisherKgPerBag': 50.0,
                'feedTotalKg': 1000.0,
                'remainingFeed': '2',
                'enteredBy': 'Guest',
                'timestamp': _iso(batch1Start.add(const Duration(days: 5))),
              },
              {
                'type': 'cost',
                'entryId': 'demo_e2',
                'date': _ddmmyyyy(batch1Start.add(const Duration(days: 12))),
                'transactionDate': _ddmmyyyy(
                  batch1Start.add(const Duration(days: 12)),
                ),
                'createdAt': _iso(batch1Start.add(const Duration(days: 12))),
                'weight': '0.85',
                'mortality': '5',
                'feed': '35',
                'feedStarterBags': 0,
                'feedGrowerBags': 35,
                'feedFinisherBags': 0,
                'feedStarterKgPerBag': 50.0,
                'feedGrowerKgPerBag': 50.0,
                'feedFinisherKgPerBag': 50.0,
                'feedTotalKg': 1750.0,
                'remainingFeed': '3',
                'enteredBy': 'Guest',
                'timestamp': _iso(batch1Start.add(const Duration(days: 12))),
              },
              {
                'type': 'cost',
                'entryId': 'demo_e3',
                'date': _ddmmyyyy(batch1Start.add(const Duration(days: 18))),
                'transactionDate': _ddmmyyyy(
                  batch1Start.add(const Duration(days: 18)),
                ),
                'createdAt': _iso(batch1Start.add(const Duration(days: 18))),
                'weight': '1.10',
                'mortality': '3',
                'feed': '40',
                'feedStarterBags': 0,
                'feedGrowerBags': 0,
                'feedFinisherBags': 40,
                'feedStarterKgPerBag': 50.0,
                'feedGrowerKgPerBag': 50.0,
                'feedFinisherKgPerBag': 50.0,
                'feedTotalKg': 2000.0,
                'remainingFeed': '5',
                'enteredBy': 'Guest',
                'timestamp': _iso(batch1Start.add(const Duration(days: 18))),
              },
            ],
          },
        ],
      },
      {
        'id': 'demo_farmer_2',
        'name': 'Suresh Yadav (Demo)',
        'phone': '9999900002',
        'district': 'Muzaffarpur',
        'state': 'Bihar',
        'status': 'active',
        'dob': '20/03/1980',
        'aadhaar': '999900002222',
        'bankName': 'PNB',
        'accountHolder': 'Suresh Yadav',
        'accountNumber': '99990000222233',
        'ifsc': 'PUNB0002345',
        'batches': [
          {
            'id': 'demo_batch_2',
            'batchId': 'demo_batch_2',
            'status': 'ACTIVE',
            'chicksCount': 3500,
            'chicksRate': 40.0,
            'totalChicksCost': '140000.00',
            'startDate': _ddmmyyyy(batch2Start),
            'dailyEntries': [
              {
                'type': 'cost',
                'entryId': 'demo_e4',
                'date': _ddmmyyyy(batch2Start.add(const Duration(days: 25))),
                'transactionDate': _ddmmyyyy(
                  batch2Start.add(const Duration(days: 25)),
                ),
                'createdAt': _iso(batch2Start.add(const Duration(days: 25))),
                'weight': '1.60',
                'mortality': '12',
                'feed': '60',
                'feedStarterBags': 0,
                'feedGrowerBags': 0,
                'feedFinisherBags': 60,
                'feedStarterKgPerBag': 50.0,
                'feedGrowerKgPerBag': 50.0,
                'feedFinisherKgPerBag': 50.0,
                'feedTotalKg': 3000.0,
                'remainingFeed': '4',
                'enteredBy': 'Guest',
                'timestamp': _iso(batch2Start.add(const Duration(days: 25))),
              },
            ],
          },
        ],
      },
      {
        'id': 'demo_farmer_3',
        'name': 'Anita Devi (Demo)',
        'phone': '9999900003',
        'district': 'Gaya',
        'state': 'Bihar',
        'status': 'active',
        'dob': '10/01/1990',
        'aadhaar': '999900003333',
        'bankName': 'HDFC',
        'accountHolder': 'Anita Devi',
        'accountNumber': '99990000333344',
        'ifsc': 'HDFC0003456',
        'batches': [
          {
            'id': 'demo_batch_3',
            'batchId': 'demo_batch_3',
            'status': 'COMPLETED',
            'chicksCount': 4000,
            'chicksRate': 40.0,
            'totalChicksCost': '160000.00',
            'startDate': _ddmmyyyy(batch3Start),
            'completedOn': _iso(batch3End),
            'dailyEntries': [
              {
                'type': 'cost',
                'entryId': 'demo_e5',
                'date': _ddmmyyyy(batch3Start.add(const Duration(days: 40))),
                'transactionDate': _ddmmyyyy(
                  batch3Start.add(const Duration(days: 40)),
                ),
                'createdAt': _iso(batch3Start.add(const Duration(days: 40))),
                'weight': '1.85',
                'mortality': '15',
                'feed': '110',
                'feedStarterBags': 0,
                'feedGrowerBags': 0,
                'feedFinisherBags': 110,
                'feedStarterKgPerBag': 50.0,
                'feedGrowerKgPerBag': 50.0,
                'feedFinisherKgPerBag': 50.0,
                'feedTotalKg': 5500.0,
                'remainingFeed': '0',
                'enteredBy': 'Guest',
                'timestamp': _iso(batch3Start.add(const Duration(days: 40))),
              },
              {
                'type': 'sale',
                'entryId': 'demo_e6',
                'date': _ddmmyyyy(batch3End),
                'transactionDate': _ddmmyyyy(batch3End),
                'createdAt': _iso(batch3End),
                'buyerName': 'Local Vyapari (Demo)',
                'chicksSold': '3985',
                'totalWeightSold': '7372.25',
                'pricePerKg': '115',
                'avgWeightSold': '1.850',
                'totalMoney': '847808.75',
                'enteredBy': 'Guest',
                'enteredByRoleAtEntry': 'Guest',
                'timestamp': _iso(batch3End),
                'appliedRuleIdAtSale': 1,
                'sizeCategoryAtSale': 'big',
                'adminRateAtSale': 1.5,
              },
            ],
            'finalSettlementSnapshot': {
              'ruleSnapshot': {
                'ruleId': 1,
                'sizeCategory': 'big',
                'feedRate': 42.0,
                'chicksRate': 40.0,
                'adminCost': 1.5,
                'kgPerBag': 50.0,
                'targetCost': 85.0,
                'baseComm': 8.0,
                'savingsShare': 50.0,
                'exceededShare': 50.0,
                'rateBonusThresh': 110.0,
                'rateBonusShare': 10.0,
                'medicineInProd': true,
              },
              'initialChicks': 4000,
              'totalMortality': 15,
              'totalChicksSold': 3985,
              'totalWeightSoldKg': 7372.25,
              'totalSaleMoney': 847808.75,
              'avgSaleRate': 115.0,
              'totalFeedBags': 110,
              'totalFeedKg': 5500.0,
              'totalChickCost': 160000.0,
              'totalFeedCost': 231000.0,
              'totalAdminCost': 11058.38,
              'totalMedicineCost': 3200.0,
              'totalProdCost': 405258.38,
              'actualCostPerKg': 54.97,
              'targetCostPerKg': 85.0,
              'costDiff': 30.03,
              'baseCommPerKg': 8.0,
              'costAdjPerKg': 15.02,
              'rateBonusApplied': true,
              'rateBonusPerKg': 0.5,
              'finalCommPerKg': 23.52,
              'grossEarning': 173428.32,
              'netPayout': 173428.32,
              'generatedAt': _iso(batch3End),
            },
          },
        ],
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 2️⃣ CHICKS PURCHASE HISTORY (with allocations)
    // ═══════════════════════════════════════════════════════════
    final demoChicksPurchase = [
      {
        'company': 'Suguna Hatchery (Demo)',
        'breed': 'Vencobb 400',
        'quantity': 12800.0,
        'billedQty': 12500.0,
        'freeQty': 300.0,
        'rate': 40.0,
        'transportCost': 2500.0,
        'totalAmount': 502500.0,
        'effectiveRate': 39.26,
        'addedByRole': 'Guest',
        'addedByName': 'Guest User',
        'date': _iso(now.subtract(const Duration(days: 32))),
        'allocations': [
          {
            'name': 'Ramesh Kumar (Demo)',
            'mobile': '',
            'qty': 5000.0,
            'rate': 40.0,
            'paid': 0.0,
            'type': 'Company',
            'allocatedOn': _iso(batch1Start),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
            'farmerId': 'demo_farmer_1',
            'batchId': 'demo_batch_1',
          },
          {
            'name': 'Suresh Yadav (Demo)',
            'mobile': '',
            'qty': 3500.0,
            'rate': 40.0,
            'paid': 0.0,
            'type': 'Company',
            'allocatedOn': _iso(batch2Start),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
            'farmerId': 'demo_farmer_2',
            'batchId': 'demo_batch_2',
          },
          {
            'name': 'Anita Devi (Demo)',
            'mobile': '',
            'qty': 4000.0,
            'rate': 40.0,
            'paid': 0.0,
            'type': 'Company',
            'allocatedOn': _iso(batch3Start),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
            'farmerId': 'demo_farmer_3',
            'batchId': 'demo_batch_3',
          },
          {
            'name': 'Local Poultry Shop (Demo)',
            'mobile': '9999955555',
            'qty': 300.0,
            'rate': 45.0,
            'paid': 13500.0,
            'type': 'Private',
            'allocatedOn': _iso(now.subtract(const Duration(days: 30))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
        ],
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 3️⃣ FEED STOCK LIST (starter/grower/finisher — new system)
    // ═══════════════════════════════════════════════════════════
    final demoFeedStock = [
      {
        'id': 'starter',
        'name': 'Starter Feed',
        'unit': 'bag',
        'totalBags': 60.0,
        'weightedAvgCost': 1250.0,
        'migratedFromOldLots': true,
        'purchaseHistory': [
          {
            'id': 'demo_feed_p1',
            'company': 'Godrej Agrovet (Demo)',
            'bags': 60.0,
            'perBagPrice': 1250.0,
            'date': _iso(now.subtract(const Duration(days: 33))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
        'allocations': [
          {
            'id': 'demo_feed_a1',
            'groupId': 'demo_feed_g1',
            'farmerName': 'Ramesh Kumar (Demo)',
            'farmerId': 'demo_farmer_1',
            'batchId': 'demo_batch_1',
            'qty': 20.0,
            'rate': 1300.0,
            'costAtAllocation': 1250.0,
            'allocatedOn': _iso(batch1Start.add(const Duration(days: 5))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
        ],
        'privateSales': [],
      },
      {
        'id': 'grower',
        'name': 'Grower Feed',
        'unit': 'bag',
        'totalBags': 80.0,
        'weightedAvgCost': 1300.0,
        'migratedFromOldLots': true,
        'purchaseHistory': [
          {
            'id': 'demo_feed_p2',
            'company': 'Godrej Agrovet (Demo)',
            'bags': 80.0,
            'perBagPrice': 1300.0,
            'date': _iso(now.subtract(const Duration(days: 20))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
        'allocations': [
          {
            'id': 'demo_feed_a2',
            'groupId': 'demo_feed_g2',
            'farmerName': 'Ramesh Kumar (Demo)',
            'farmerId': 'demo_farmer_1',
            'batchId': 'demo_batch_1',
            'qty': 35.0,
            'rate': 1350.0,
            'costAtAllocation': 1300.0,
            'allocatedOn': _iso(batch1Start.add(const Duration(days: 12))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
        ],
        'privateSales': [
          {
            'id': 'demo_feed_ps1',
            'buyerName': 'Village Poultry Store (Demo)',
            'mobile': '9999966666',
            'qty': 10.0,
            'rate': 1400.0,
            'paidAmount': 14000.0,
            'date': _iso(now.subtract(const Duration(days: 10))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
      },
      {
        'id': 'finisher',
        'name': 'Finisher Feed',
        'unit': 'bag',
        'totalBags': 210.0,
        'weightedAvgCost': 1280.0,
        'migratedFromOldLots': true,
        'purchaseHistory': [
          {
            'id': 'demo_feed_p3',
            'company': 'Godrej Agrovet (Demo)',
            'bags': 210.0,
            'perBagPrice': 1280.0,
            'date': _iso(now.subtract(const Duration(days: 15))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
        'allocations': [
          {
            'id': 'demo_feed_a3',
            'groupId': 'demo_feed_g3',
            'farmerName': 'Ramesh Kumar (Demo)',
            'farmerId': 'demo_farmer_1',
            'batchId': 'demo_batch_1',
            'qty': 40.0,
            'rate': 1320.0,
            'costAtAllocation': 1280.0,
            'allocatedOn': _iso(batch1Start.add(const Duration(days: 18))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
          {
            'id': 'demo_feed_a4',
            'groupId': 'demo_feed_g4',
            'farmerName': 'Suresh Yadav (Demo)',
            'farmerId': 'demo_farmer_2',
            'batchId': 'demo_batch_2',
            'qty': 60.0,
            'rate': 1320.0,
            'costAtAllocation': 1280.0,
            'allocatedOn': _iso(batch2Start.add(const Duration(days: 25))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
          {
            'id': 'demo_feed_a5',
            'groupId': 'demo_feed_g5',
            'farmerName': 'Anita Devi (Demo)',
            'farmerId': 'demo_farmer_3',
            'batchId': 'demo_batch_3',
            'qty': 110.0,
            'rate': 1320.0,
            'costAtAllocation': 1280.0,
            'allocatedOn': _iso(batch3Start.add(const Duration(days: 40))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
        ],
        'privateSales': [],
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 4️⃣ MEDICINE STOCK LIST
    // ═══════════════════════════════════════════════════════════
    final demoMedicineStock = [
      {
        'id': 'demo_med_1',
        'name': 'Enrofloxacin (Demo)',
        'nickName': 'Enro',
        'unit': 'ml',
        'totalBaseQty': 2000.0,
        'weightedAvgCost': 2.5,
        'currentFarmerRate': 3.0,
        'addedByName': 'Guest User',
        'addedByRole': 'Guest',
        'createdOn': _iso(now.subtract(const Duration(days: 25))),
        'allocations': [
          {
            'id': 'demo_med_a1',
            'farmerName': 'Ramesh Kumar (Demo)',
            'farmerId': 'demo_farmer_1',
            'batchId': 'demo_batch_1',
            'qty': 500.0,
            'unit': 'ml',
            'qtyInBaseUnit': 500.0,
            'rate': 3.0,
            'ratePerBase': 3.0,
            'costAtAllocation': 2.5,
            'allocatedOn': _iso(batch1Start.add(const Duration(days: 10))),
            'allocatedByName': 'Guest User',
            'allocatedByRole': 'Guest',
          },
        ],
        'purchaseHistory': [
          {
            'id': 'demo_med_p1',
            'qty': 2000.0,
            'unit': 'ml',
            'qtyInBaseUnit': 2000.0,
            'actualPrice': 5000.0,
            'farmerPrice': 6000.0,
            'perBaseActualCost': 2.5,
            'perBaseFarmerRate': 3.0,
            'date': _iso(now.subtract(const Duration(days: 25))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
      },
      {
        'id': 'demo_med_2',
        'name': 'Vitamin B-Complex (Demo)',
        'nickName': 'VitB',
        'unit': 'ml',
        'totalBaseQty': 1000.0,
        'weightedAvgCost': 1.2,
        'currentFarmerRate': 1.5,
        'addedByName': 'Guest User',
        'addedByRole': 'Guest',
        'createdOn': _iso(now.subtract(const Duration(days: 20))),
        'allocations': [],
        'purchaseHistory': [
          {
            'id': 'demo_med_p2',
            'qty': 1000.0,
            'unit': 'ml',
            'qtyInBaseUnit': 1000.0,
            'actualPrice': 1200.0,
            'farmerPrice': 1500.0,
            'perBaseActualCost': 1.2,
            'perBaseFarmerRate': 1.5,
            'date': _iso(now.subtract(const Duration(days: 20))),
            'addedByName': 'Guest User',
            'addedByRole': 'Guest',
          },
        ],
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 5️⃣ MEDICINE PRIVATE SALES
    // ═══════════════════════════════════════════════════════════
    final demoMedicineSales = [
      {
        'id': 'demo_medsale_1',
        'buyerName': 'Nearby Farm Owner (Demo)',
        'mobile': '9999977777',
        'date': _iso(now.subtract(const Duration(days: 8))),
        'items': [
          {
            'medicineId': 'demo_med_1',
            'medicineName': 'Enrofloxacin (Demo)',
            'nickName': 'Enro',
            'qty': 200.0,
            'saleUnit': 'ml',
            'qtyInBaseUnit': 200.0,
            'saleRate': 3.5,
            'totalSale': 700.0,
            'totalCost': 500.0,
          },
        ],
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 6️⃣ LABOUR + OTHER EXPENSES
    // ═══════════════════════════════════════════════════════════
    final demoLabourExpense = [
      {
        'workerName': 'Mohan Mistri (Demo)',
        'labourType': 'Shed Repair',
        'unitMode': 'Din',
        'quantity': 3,
        'rate': 500.0,
        'totalAmount': 1500.0,
        'note': 'Shed ki chhat theek karwayi',
        'addedByRole': 'Guest',
        'addedByName': 'Guest User',
        'date': _iso(now.subtract(const Duration(days: 14))),
        'mobile': '',
        'aadhaar': '',
        'pan': '',
        'bankName': '',
        'accountNo': '',
        'ifsc': '',
      },
      {
        'workerName': 'Field Supervisor (Demo)',
        'labourType': 'Manager - Farm',
        'unitMode': 'Monthly',
        'quantity': 1,
        'rate': 15000.0,
        'totalAmount': 15000.0,
        'note': 'Maheene ki salary',
        'addedByRole': 'Guest',
        'addedByName': 'Guest User',
        'date': _iso(now.subtract(const Duration(days: 3))),
        'mobile': '',
        'aadhaar': '',
        'pan': '',
        'bankName': '',
        'accountNo': '',
        'ifsc': '',
      },
    ];

    final demoOtherExpense = [
      {
        'expenseType': 'Electricity Bill',
        'amount': 4500.0,
        'note': 'Farm ka bijli bill',
        'addedByRole': 'Guest',
        'addedByName': 'Guest User',
        'date': _iso(now.subtract(const Duration(days: 6))),
      },
      {
        'expenseType': 'Transport/Fuel',
        'amount': 2200.0,
        'note': 'Feed transport kharcha',
        'addedByRole': 'Guest',
        'addedByName': 'Guest User',
        'date': _iso(now.subtract(const Duration(days: 4))),
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 7️⃣ ACTIVITY LOGS
    // ═══════════════════════════════════════════════════════════
    final demoActivityLogs = [
      {
        'module': 'Batch',
        'actionType': 'UPDATE',
        'message':
            'Batch demo_batch_3 permanently close kar diya gaya aur settlement complete hua.',
        'performedByName': 'Guest User',
        'performedByRole': 'Guest',
        'timestamp': _iso(batch3End),
      },
      {
        'module': 'Feed',
        'actionType': 'ADD',
        'message':
            'Naya finisher feed kharida gaya: 210 Bags @ ₹1280/bag company "Godrej Agrovet (Demo)" se',
        'performedByName': 'Guest User',
        'performedByRole': 'Guest',
        'timestamp': _iso(now.subtract(const Duration(days: 15))),
      },
      {
        'module': 'Batch',
        'actionType': 'ADD',
        'message':
            'Farmer "Suresh Yadav (Demo)" ke liye naya batch shuru kiya gaya: 3500 birds.',
        'performedByName': 'Guest User',
        'performedByRole': 'Guest',
        'timestamp': _iso(batch2Start),
      },
      {
        'module': 'Medicine',
        'actionType': 'ADD',
        'message':
            'Medicine "Enrofloxacin (Demo)" kharidi gayi: 2000 ml @ ₹5000',
        'performedByName': 'Guest User',
        'performedByRole': 'Guest',
        'timestamp': _iso(now.subtract(const Duration(days: 25))),
      },
      {
        'module': 'Batch',
        'actionType': 'ADD',
        'message':
            'Farmer "Ramesh Kumar (Demo)" ke liye naya batch shuru kiya gaya: 5000 birds.',
        'performedByName': 'Guest User',
        'performedByRole': 'Guest',
        'timestamp': _iso(batch1Start),
      },
    ];

    // ═══════════════════════════════════════════════════════════
    // 8️⃣ SETTLEMENT CONFIG (Rule 1 applied)
    // ═══════════════════════════════════════════════════════════
    final demoRule1Config = {
      'bigFeedRate': 42.0,
      'bigChicksRate': 40.0,
      'bigAdminCost': 1.50,
      'bigKgPerBag': 50.0,
      'bigTargetCost': 85.0,
      'bigBaseComm': 8.0,
      'bigSavingsShare': 50.0,
      'bigExceededShare': 50.0,
      'bigRateBonusThresh': 110.0,
      'bigRateBonusShare': 10.0,
      'bigMedicineInProd': true,
      'smFeedRate': 42.0,
      'smChicksRate': 40.0,
      'smAdminCost': 1.50,
      'smKgPerBag': 50.0,
      'smTargetCost': 90.0,
      'smBaseComm': 10.0,
      'smSavingsShare': 50.0,
      'smExceededShare': 50.0,
      'smRateBonusThresh': 120.0,
      'smRateBonusShare': 10.0,
      'smMedicineInProd': true,
    };

    // ═══════════════════════════════════════════════════════════
    // SAVE EVERYTHING
    // ═══════════════════════════════════════════════════════════
    await CompanyStore.instance.saveJsonList('companyFarmers', demoFarmers);
    await CompanyStore.instance.setString(
      'chicksPurchaseHistory',
      json.encode(demoChicksPurchase),
    );
    await CompanyStore.instance.saveJsonList('feedStockList', demoFeedStock);
    await CompanyStore.instance.setString(
      'medicineStockList',
      json.encode(demoMedicineStock),
    );
    await CompanyStore.instance.setString(
      'medicineSalesHistory',
      json.encode(demoMedicineSales),
    );
    await CompanyStore.instance.setString(
      'labourExpenseHistory',
      json.encode(demoLabourExpense),
    );
    await CompanyStore.instance.setString(
      'otherExpenseHistory',
      json.encode(demoOtherExpense),
    );
    await CompanyStore.instance.setString(
      'globalActivityLogs',
      json.encode(demoActivityLogs),
    );
    await CompanyStore.instance.setString(
      'rule1SettlementConfig',
      json.encode(demoRule1Config),
    );
    await CompanyStore.instance.setInt('appliedCompanyRuleId', 1);
    await CompanyStore.instance.setInt('minLiftingDays', 23);
    await CompanyStore.instance.setInt('maxLiftingDays', 60);
    // Legacy key clear (naya feedStockList system use hota hai)
    await CompanyStore.instance.setString(
      'feedStockMap',
      json.encode({'Starter': 0.0, 'Grower': 0.0, 'Finisher': 0.0}),
    );
  }
}
