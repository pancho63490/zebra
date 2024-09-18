import UIKit
import CoreBluetooth
import ExternalAccessory

class ViewController: UIViewController, CBCentralManagerDelegate {

    @IBOutlet weak var printerListTable: UITableView!
    
    var centralManager: CBCentralManager!
    var connectedAccessories: [EAAccessory] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Inicializar CBCentralManager para manejar el estado de Bluetooth
        print("viewDidLoad: Vista cargada, comenzando a inicializar CBCentralManager.")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("centralManagerDidUpdateState: Bluetooth está encendido.")
            self.updateConnectedAccessories() // Actualizar accesorios conectados si Bluetooth está encendido
        case .poweredOff:
            print("centralManagerDidUpdateState: Bluetooth está apagado. Pide al usuario que lo active.")
        case .resetting:
            print("centralManagerDidUpdateState: Bluetooth se está reiniciando.")
        case .unauthorized:
            print("centralManagerDidUpdateState: La app no tiene permisos para usar Bluetooth.")
        case .unsupported:
            print("centralManagerDidUpdateState: El dispositivo no soporta Bluetooth.")
        case .unknown:
            print("centralManagerDidUpdateState: Estado desconocido de Bluetooth.")
        @unknown default:
            print("centralManagerDidUpdateState: Estado no manejado.")
        }
    }
    
    @IBAction func refreshBtnTouchUp(_ sender: Any) {
        print("refreshBtnTouchUp: Botón de refresco presionado.")
        updateConnectedAccessories()
        printerListTable.reloadData()
    }
    
    // Actualizar accesorios conectados
    private func updateConnectedAccessories() {
        connectedAccessories = EAAccessoryManager.shared().connectedAccessories
        if connectedAccessories.isEmpty {
            print("updateConnectedAccessories: No se encontraron impresoras conectadas.")
        } else {
            for accessory in connectedAccessories {
                print("Accesorio encontrado: \(accessory.name) \(accessory.modelNumber) \(accessory.serialNumber)")
            }
        }
    }
}

extension ViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return connectedAccessories.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "Cell"
        var cell: UITableViewCell!
        cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: cellIdentifier)
        }
        
        let eaAccessory = connectedAccessories[indexPath.row]
        cell.textLabel?.text = "\(eaAccessory.name) \(eaAccessory.modelNumber) \(eaAccessory.serialNumber)"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("didSelectRowAt: Impresora seleccionada en el índice \(indexPath.row).")
        self.connectEaAccessory(eaAccessory: connectedAccessories[indexPath.row])
    }
}

extension ViewController {

    private func connectEaAccessory(eaAccessory: EAAccessory) {
        print("connectEaAccessory: Intentando conectar con la impresora \(eaAccessory.name) \(eaAccessory.modelNumber).")
        
        if eaAccessory.modelNumber.hasPrefix("ZQ630") {
            print("connectEaAccessory: Es una impresora Zebra ZQ620. Intentando conexión...")
            
            // Zebra SDK requires communication in background thread
            DispatchQueue.global(qos: .background).async {
                guard let connection = MfiBtPrinterConnection(serialNumber: eaAccessory.serialNumber) else {
                    print("connectEaAccessory: Error al inicializar la conexión Bluetooth.")
                    return
                }
                
                if connection.open() {
                    print("connectEaAccessory: Conexión exitosa con la impresora \(eaAccessory.name).")
                    do {
                        var printer: ZebraPrinter & NSObjectProtocol
                        printer = try ZebraPrinterFactory.getInstance(connection)
                        
                        let printerLanguage = printer.getControlLanguage()
                        print("La impresora usa el siguiente lenguaje: \(printerLanguage)")
                        
                        if printerLanguage == PRINTER_LANGUAGE_ZPL {
                            print("Conectado con ZPL. Configurando y enviando comandos de prueba.")
                            self.configureLabelSize(connection: connection)
                            self.sendZebraTestingString(connection: connection)
                        } else {
                            print("Conectado, pero la impresora no usa ZPL.")
                        }
                        
                    } catch {
                        print("Error al obtener la instancia de la impresora: \(error.localizedDescription)")
                    }
                } else {
                    print("Error al abrir la conexión con la impresora \(eaAccessory.name).")
                }
            }
        } else {
            print("connectEaAccessory: El accesorio seleccionado no es una impresora ZQ620.")
        }
    }
    
    private func sendStrToPrinter(_ strToSend: String, connection: ZebraPrinterConnection) {
        let data = strToSend.data(using: .utf8)!
        var error: NSErrorPointer = nil
        connection.write(data, error: error)
        if let err = error {
            print("Error al enviar los datos a la impresora: \(err.debugDescription)")
        } else {
            print("Datos enviados exitosamente a la impresora.")
        }
    }
    
    private func configureLabelSize(connection: ZebraPrinterConnection) {
        let strToSend = """
        ^XA
        ^PW408
        ^LT16
        ^XZ
        """
        sendStrToPrinter(strToSend, connection: connection)
    }
    
    private func sendZebraTestingString(connection: ZebraPrinterConnection) {
        let testingStr = "^XA^FO50,50^ADN,36,20^FDTEST^FS^XZ"
        sendStrToPrinter(testingStr, connection: connection)
    }
}
