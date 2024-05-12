import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart' as web;

class FlutterBluePlusWeb {
  static late Future<dynamic> Function(MethodCall) _methodCallHandler;

  static Map<DeviceIdentifier, web.BluetoothDevice> _devices = {};

  static setMethodCallHandler(methodCallHandler) {
    _methodCallHandler = methodCallHandler;
  }

  static Future invokeMethod(String method, [dynamic arguments]) async {
    if (method == "setOptions") {
    } else if (method == "flutterRestart") {
      // disconnect all devices
      web.FlutterWebBluetooth.instance.devices.forEach((device) {
        device.forEach((element) {
          element.disconnect();
        });
      });
      var remaining = await web.FlutterWebBluetooth.instance.devices.first;
      return remaining.length;
    } else if (method == "connectedCount") {
    } else if (method == "setLogLevel") {
    } else if (method == "isSupported") {
    } else if (method == "getAdapterState") {
      bool supported = web.FlutterWebBluetooth.instance.isBluetoothApiSupported;
      Map<String, dynamic> map = {};
      if (!supported) {
        map["adapter_state"] = BmAdapterStateEnum.unavailable.index;
      } else {
        map["adapter_state"] = BmAdapterStateEnum.on.index;
      }
      return map;
    } else if (method == "turnOn") {
    } else if (method == "turnOff") {
    } else if (method == "startScan") {
      // parse arguments
      var settings = BmScanSettings.fromMap(arguments);
      if (settings.withServices.length != 1) {
        throw FlutterBluePlusException(ErrorPlatform.web, "startScan", -1, "on web, you must specify 1 withServices");
      }

      // filter
      var filterService = web.RequestFilterBuilder(services: [settings.withServices.first.str128]);

      // todo: support other filters

      // options
      var options = web.RequestOptionsBuilder([filterService]);

      // scan
      web.BluetoothDevice device = await web.FlutterWebBluetooth.instance.requestDevice(options);

      // remember device
      _devices[DeviceIdentifier(device.id)] = device;

      // convert to advertisement
      var adv = BmScanAdvertisement(
        remoteId: DeviceIdentifier(device.id),
        platformName: device.name ?? "Unknown",
        advName: device.name ?? "Unknown",
        connectable: true,
        txPowerLevel: 0,
        appearance: 0,
        manufacturerData: {},
        serviceData: {},
        serviceUuids: [],
        rssi: 0,
      );

      var advMap = adv.toMap();
      advMap["remote_id"] = device.id;

      _methodCallHandler(MethodCall("OnScanResponse", {
        "advertisements": [advMap]
      }));
      print("OnScanResponse done : ${adv.toMap()}");
      return true;
    } else if (method == "stopScan") {
      //TODO should we stop something ?
      return true;
    } else if (method == "getSystemDevices") {
      List<Map<String, dynamic>> devices = [];
      var webDevices = await web.FlutterWebBluetooth.instance.devices.first;
      webDevices.forEach((device) {
        devices.add({
          "id": device.id,
          "platform_name": device.name,
        });
      });
      var response = {"devices": devices};
      return response;
    } else if (method == "connect") {
      String remoteId = ""; //arguments["remote_id"];
      bool autoConnect = false; //arguments["auto_connect"];
      arguments.forEach((key, value) {
        if (key == "remote_id") {
          remoteId = value;
        } else if (key == "auto_connect") {
          autoConnect = value == 1;
        }
      });
      //TODO check if device is known
      web.BluetoothDevice device = _devices[DeviceIdentifier(remoteId)]!;

      try {
        var connected = await device.connected.first;
        if (connected) {
          //nothing has changed
          return false;
        }
        await device.connect();
        device.connected.first.then((value) {
          _methodCallHandler(MethodCall("OnConnectionStateChanged", {
            "remote_id": remoteId,
            "connection_state":
                value ? BmConnectionStateEnum.connected.index : BmConnectionStateEnum.disconnected.index,
            "disconnect_reason_code": 0,
            "disconnect_reason_string": "",
          }));
        });

        return true;
      } on web.NetworkError {
        throw FlutterBluePlusException(ErrorPlatform.web, "connect", -1, "network error");
      } on StateError {
        throw FlutterBluePlusException(ErrorPlatform.web, "connect", -1, "state error");
      } catch (e) {
        throw FlutterBluePlusException(ErrorPlatform.web, "connect", -1, e.toString());
      }
    } else if (method == "disconnect") {
    } else if (method == "discoverServices") {
      var remoteId = arguments as String;
      web.BluetoothDevice device = _devices[DeviceIdentifier(remoteId)]!;
      device.discoverServices().then((services) async {
        List<Map<String, dynamic>> servicesList = [];

        for (var service in services) {
          var characs = await service.getCharacteristics();
          List<dynamic> characList = [];
          for (var charac in characs) {
            List<dynamic> descriptorsList = [];
            /*
            var descriptors = await charac.getDescriptors();
            
            for (var descriptor in descriptors) {
              descriptorsList.add({
                "remote_id": remoteId,
                "service_uuid": service.uuid,
                "characteristic_uuid": charac.uuid,
                "descriptor_uuid": descriptor.uuid,
              });
            }
            */
            characList.add({
              "remote_id": remoteId,
              "service_uuid": service.uuid,
              "characteristic_uuid": charac.uuid,
              "properties": {
                'broadcast': charac.properties.broadcast ? 1 : 0,
                'read': charac.properties.read ? 1 : 0,
                'write_without_response': charac.properties.writeWithoutResponse ? 1 : 0,
                'write': charac.properties.write ? 1 : 0,
                'notify': charac.properties.notify ? 1 : 0,
                'indicate': charac.properties.indicate ? 1 : 0,
                'authenticated_signed_writes': charac.properties.authenticatedSignedWrites ? 1 : 0,
                'extended_properties': charac.properties.hasProperties ? 1 : 0, //TODO check if it is correct
                'notify_encryption_required': 0, //TODO search how to get this information
                'indicate_encryption_required': 0, //TODO search how to get this information
              },
              "descriptors": descriptorsList,
            });
          }

          servicesList.add({
            "remote_id": remoteId,
            "service_uuid": service.uuid,
            "is_primary": service.isPrimary,
            "characteristics": characList,
            "included_services": [], //TODO get information
          });
        }

        _methodCallHandler(MethodCall("OnDiscoveredServices", {
          "remote_id": remoteId,
          "services": servicesList,
          "success": 1, //TODO deal with errors
          "error_code": 0,
          "error_string": "",
        }));
      });
      return true;
    } else if (method == "readCharacteristic") {
    } else if (method == "writeCharacteristic") {
    } else if (method == "readDescriptor") {
    } else if (method == "writeDescriptor") {
    } else if (method == "setNotifyValue") {
    } else if (method == "requestMtu") {
    } else if (method == "readRssi") {
      var remoteId = arguments as String;
      web.BluetoothDevice device = _devices[DeviceIdentifier(remoteId)]!;
      if (device.hasWatchAdvertisements()) {
        device.watchAdvertisements();
        device.advertisements.listen((event) {
          _methodCallHandler(MethodCall("OnReadRssi", {
            "remote_id": remoteId,
            "rssi": event.rssi,
            "success": 1,
            "error_code": 0,
            "error_string": "",
          }));
        });
      } else {
        throw FlutterBluePlusException(ErrorPlatform.web, "readRssi", -1, "not supported on web");
      }
      return true;
    } else if (method == "requestConnectionPriority") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "requestConnectionPriority", -1, "not supported on web");
    } else if (method == "getPhySupport") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "getPhySupport", -1, "not supported on web");
    } else if (method == "setPreferredPhy") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "setPreferredPhy", -1, "not supported on web");
    } else if (method == "getBondedDevices") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "getBondedDevices", -1, "not supported on web");
    } else if (method == "createBond") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "createBond", -1, "not supported on web");
    } else if (method == "removeBond") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "removeBond", -1, "not supported on web");
    } else if (method == "clearGattCache") {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, "clearGattCache", -1, "not supported on web");
    } else {
      // unsupported
      throw FlutterBluePlusException(ErrorPlatform.web, method, -1, "not supported on web");
    }

    return Future.delayed(Duration.zero);
  }
}
