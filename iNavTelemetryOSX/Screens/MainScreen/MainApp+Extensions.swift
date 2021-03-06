//
//  MainApp+Extensions.swift
//  iNavTelemetryOSX
//
//  Created by Bosko Petreski on 10/24/20.
//  Copyright © 2020 Bosko Petreski. All rights reserved.
//

import Cocoa
import CoreBluetooth
import MapKit
import AVFoundation

extension MainApp : AVCapturePhotoCaptureDelegate {
    // MARK: - CapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let imageData = photo.fileDataRepresentation()
        if let data = imageData {
            tempCapturePhotoCamera = data.base64EncodedString()
        }
    }
}

extension MainApp : MKMapViewDelegate{
    // MARK: - MAPViewDelegate
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKTileOverlay {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            return renderer
        } else {
            if let routePolyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: routePolyline)
                renderer.strokeColor = NSColor.red
                renderer.lineWidth = 2
                return renderer
            }
        }
        return MKTileOverlayRenderer()
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if !(annotation is LocationPointAnnotation) {
            return nil
        }
        let reuseId = "LocationPin"
        var anView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
        if anView == nil {
            anView = MKAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            anView?.canShowCallout = true
        }
        else {
            anView?.annotation = annotation
        }
        
        let cpa = annotation as! LocationPointAnnotation
        if cpa.imageName != nil{
            anView?.image = NSImage(named:cpa.imageName)
        }
        return anView
    }
}
extension MainApp : CBCentralManagerDelegate, CBPeripheralDelegate {
    //MARK: CentralManagerDelegates
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        var message = "Bluetooth"
        switch (central.state) {
        case .unknown: message = "Bluetooth Unknown."; break
        case .resetting: message = "The update is being started. Please wait until Bluetooth is ready."; break
        case .unsupported: message = "This device does not support Bluetooth low energy."; break
        case .unauthorized: message = "This app is not authorized to use Bluetooth low energy."; break
        case .poweredOff: message = "You must turn on Bluetooth in Settings in order to use the reader."; break
        default: break;
        }
        print("Bluetooth: " + message);
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !peripherals.contains(peripheral){
            peripherals.append(peripheral)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedPeripheral.delegate = self
        connectedPeripheral.discoverServices([CBUUID (string: "FFE0")])
        btnConnect.image = NSImage(named: "power_on")
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if error != nil {
            print("FailToConnect" + error!.localizedDescription)
        }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if error != nil {
            print("FailToDisconnect" + error!.localizedDescription)
            centralManager.cancelPeripheralConnection(connectedPeripheral)
            peripherals.removeAll()
            
            var timeoutSeconds = 0;
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (timer) in
                timeoutSeconds += 1
                
                if self.connectedPeripheral.state == .connected {
                    print("connected....")
                    timer.invalidate();
                }
                else if self.connectedPeripheral.state == .connecting{
                    print("connecting....")
                }
                else if self.connectedPeripheral.state == .disconnecting{
                    print("disconnecting....")
                }
                else if self.connectedPeripheral.state == .disconnected{
                    print("disconnected....")
                    self.centralManager.connect(self.connectedPeripheral, options: nil)
                }
                
                if timeoutSeconds > 100 {
                    print("timeout")
                    self.connectedPeripheral = nil;
                    Database.shared.stopLogging()
                    self.btnConnect.image = NSImage(named: "power_off")
                    timer.invalidate();
                }
                
            })
        }
        
        Database.shared.stopLogging()
        btnConnect.image = NSImage(named: "power_off")
    }
    
    //MARK: PeripheralDelegates
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("Error receiving didWriteValueFor \(characteristic) : " + error!.localizedDescription)
            return
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("Error receiving notification for characteristic \(characteristic) : " + error!.localizedDescription)
            return
        }
        if telemetry.process_incoming_bytes(incomingData: characteristic.value!) {
            refreshTelemetry(packet: telemetry.packet)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services!{
            peripheral.discoverCharacteristics([CBUUID (string: "FFE1")], for: service)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("Error receiving didUpdateNotificationStateFor \(characteristic) : " + error!.localizedDescription)
            return
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics! {
            if characteristic.uuid == CBUUID(string: "FFE1"){
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
}
extension MainApp {
    // MARK: - Helpers
    func toDate(timestamp : Double) -> String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy MMM d [hh:mm]"
        let date = Date(timeIntervalSince1970: timestamp)
        return dateFormatter.string(from: date)
    }
    func openLog(urlLog : URL){
        let jsonData = try! Data(contentsOf: urlLog)
        let logData = try! JSONDecoder().decode([SmartPortStruct].self, from: jsonData)
        
        let controller : LogScreen = self.storyboard!.instantiateController(identifier: "LogScreen")
        controller.logData = logData
        self.presentAsSheet(controller)
    }
}
