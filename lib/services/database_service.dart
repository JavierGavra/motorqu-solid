import 'package:motorqu_solid/services/motorcycle_service.dart';
import 'package:motorqu_solid/services/oil_service.dart';

class DatabaseService {
  static DatabaseService? _instance;

  DatabaseService._(this.webId);

  DatabaseService.init(this.webId) {
    _instance = DatabaseService._(webId);
  }

  factory DatabaseService() => _instance!;

  String webId;

  MotorcycleService get motorcycle => MotorcycleService(webId);

  OilService get oil => OilService(webId);
}
