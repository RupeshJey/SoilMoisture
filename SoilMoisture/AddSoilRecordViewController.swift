//
//  AddSoilRecordViewController.swift
//  SoilMoisture
//
//  Created by Rupesh Jeyaram on 3/13/17.
//  Copyright © 2017 Planlet Systems. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit

import CoreBluetooth

class AddSoilRecordViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, CLLocationManagerDelegate, WeatherGetterDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate, ObservationsTableViewCellDelegate {
    
    // DECLARE VARIABLES
    
    let openedKeyID = "openedBefore",       // Constant
        userMetadataID = "userMetadata",    // Constant
        recordsID = "recordsID",            // Constant
        maxAlpha:CGFloat = 1.0,             // Maximum alpha for fade animations
        minAlpha:CGFloat = 0.4              // Minimum alpha for fade animations
    
    var invalid:String = "-------",         // Default invalid value for all strings
        date:String = "",                   // Date
        resistance:String = "",             // Sensor-measured resistance
        temperature:String = "",            // Sensor-measured temperature
        moisture:String = "",               // Sensor-measured moisture
        siteString = "",                    // Selected site string
        locManager = CLLocationManager(),   // Location Manager to get coordinates
        temp:Double?,                       // Numerical temperature
        resist:Double = 0.0,                // Numberical resistance
        image:UIImage?,                     // Image
        imageBool:Bool = false,             // Boolean for image
        shouldRefreshSensor:Bool = true,    // Boolean whether to refresh sensor
        newPin = MKPointAnnotation(),       // Point for MapKit
        soilRecord:SoilDataRecord?,         // Individual Soil Record
        nrfManagerInstance:NRFManager!,     // Connector to Arduino
        recordsArray:[Any]?,                // Array of records
        moistureNumber:Double? = 0.0,       // Numerical moisture
        timer: Timer?,                      // Timer
        coordinateRegion:MKCoordinateRegion?// Coordinates
    
    
    var mapView:MKMapView = MKMapView.init()
    var pageOpened = false
    
    struct SensorParameters {
        //units: Meters
        
        let circumference:Double = 0.0095
        let length:Double = 0.049
        let exposedLength:Double = 0.05
        
        func resistivity(r:Double) -> Double {
            return r*((exposedLength * (circumference/2)) / length)
        }
        
        func resistance(ser:Double) -> Double {
            return ser/((exposedLength * (circumference/2)) / length)
        }
    }
    
    //@IBOutlet weak var Save: UIButton!                // Save Button
    @IBOutlet weak var DataTable: UITableView!          // Data Table
    @IBOutlet weak var BlurView: UIVisualEffectView!    // Blur before Bluetooth View
    @IBOutlet weak var BluetoothView: UIView!           // Bluetooth view
    @IBOutlet weak var BluetoothImage: UIImageView!     // Bluetooth image
    @IBOutlet weak var BluetoothText: UILabel!          // Bluetooth notifying text
    @IBOutlet weak var SettingsButton:UIButton!         // Button to take user into settings
    
    // END VARIABLES
    
    // View did load
    override func viewDidLoad() {
        
        
        super.viewDidLoad()
        
        
        if self.hasOpenedBefore() {
            // Set default labels
            setupInvalids()
            
            // Set up the location manager
            locationSetup()
            
            // Listen for shifting table as necessary
            NotificationCenter.default.addObserver(self, selector: #selector(self.handleNoteTap), name: Notification.Name("shiftTable"), object: nil)
            
            // Bluetooth error-handling view setup
            bluetoothSetup()
            
            // Scheduling timer to call the bluetooth checker with the interval of 1 second
            startTimer()
            
            // Load mapview
            loadMap()
        }
        
        
    }

    // View did appear
    override func viewDidAppear(_ animated: Bool) {
        
        // Collect metadata if first load
        if !self.hasOpenedBefore() {self.getMetadata()}
        
        // Continue if not
        else {
            // Collect sensor data
            getArduinoData()
            
            // Get weather by passing coordinates
            getWeather()
            
            // Update the temporary site string
            //siteString = UserDefaults.standard.string(forKey: "tempSiteName")!
            
            // Animate the Bluetooth pulse
            animateBluetooth()
        }
    }
    
    // Load map beforehand
    
    func loadMap() {
        coordinateRegion = MKCoordinateRegionMakeWithDistance((locManager.location?.coordinate)!, 1000 * 2.0, 1000 * 2.0)
        mapView.setRegion(coordinateRegion!, animated: false)
    }
    
    // Location manager details
    func locationSetup() {
        locManager.delegate = self
        locManager.desiredAccuracy = kCLLocationAccuracyBest
        locManager.requestWhenInUseAuthorization()
        locManager.startMonitoringSignificantLocationChanges()
    }
    
    // Setup bluetooth view
    func bluetoothSetup() {
        BlurView.effect = UIBlurEffect(style: .regular)
        BluetoothView.alpha = 0.0
        BluetoothImage.image = UIImage(named: "bluetooth-symbol-silhouette_318-38721")!.withRenderingMode(.alwaysTemplate)
        BluetoothImage.tintColor = UIColor.init(red: 48.0/255.0, green: 132/255.0, blue: 244/255.0, alpha: maxAlpha)
        SettingsButton.isHidden = true
        BluetoothView.layer.cornerRadius = 15
    }
    
    // Mark the main data fields as invalid (sensor hasn't collected yet)
    func setupInvalids() {
        date = invalid
        resistance = invalid
        temperature = invalid
        moisture = invalid
    }
    
    // Get metadata if necessary
    func getMetadata() {
        
        print("getting metadata")
        
        let nextVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "InitialMetadaViewController")
        nextVC.modalTransitionStyle = .coverVertical
        self.present(nextVC, animated: true, completion: nil)
    }
    
    // Weather by passing coordinates
    func getWeather() {
        let weather = WeatherGetter.init(delegate: self)
        weather.getWeather(latitude: String(locManager.location!.coordinate.latitude), longitude: String(locManager.location!.coordinate.longitude))
    }
    
    // Helper function to tell whether app has been opened before
    func hasOpenedBefore() -> Bool {
        
        return UserDefaults.standard.bool(forKey: openedKeyID)
        
    }
    
    // This function gets valid sensor data
    
    func getArduinoData() {
        
        nrfManagerInstance = NRFManager(
            onConnect: {
                print("Connected")
        },
            onDisconnect: {
                print("Disconnected")
        },
            onData: {
                (data:Data?, string:String?)->() in
                
                // Set date string
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy, hh:mm a zz"
                self.date = formatter.string(from: Date())
                
                // Pick out the resistance and evaluate moisture
                let indexStartOfText = string!.index(string!.startIndex, offsetBy: 3)
                
                if string!.contains("R: ") {
                    self.resistance = string!.substring(from: indexStartOfText)
                    
                    if (Double(self.resistance) != nil && self.temp != nil) {
                        
                        //first obtain corrected resistance and temp
                        let initialResistance = Double(self.resistance)!
                        let finalResistance = self.normalizeResistance(resistance: initialResistance, temperature: self.temp!)
                        
                        //print("Final resistance is: \(finalResistance)")
                        
                        var moistureValue = /*611897*/ 387258 * pow(finalResistance , -1.196)
                        moistureValue = Double(round(1000*moistureValue)/1000)
                        
                        self.moistureNumber = moistureValue
                        
                        self.moisture = String(format: "%0.1f",moistureValue)
                        self.moisture.append("%")
                    }
                }
                
                else if string!.contains("T: ") {
                    let shortenedDouble = string!.substring(from: indexStartOfText)
                    if (shortenedDouble != "-196.60" && shortenedDouble != "185.00") {
                        self.temp = Double(shortenedDouble)!
                        self.temperature =  String(format: "%0.1f",self.temp!) + "℉"
                    }
                    else {
                        self.temperature = "Disconnected"
                    }
                }
                
                if (self.shouldRefreshSensor) {
                    self.DataTable.reloadData()
                }
        }
        )
        
        nrfManagerInstance.autoConnect = false
        nrfManagerInstance.connect("JPLSoil")
    }
    
    func normalizeResistance(resistance:Double, temperature:Double) -> Double {
        let alpha:Double = 0.0012
        let beta:Double = 0.1562
        
        let sensorReading:SensorParameters = SensorParameters()
        let serT = sensorReading.resistivity(r: resistance)
        let celsiusTemp = (temperature - 32 ) / 1.8
        let ser20 = serT / (1-serT*alpha*exp(beta*(celsiusTemp - 20)))
        
        return sensorReading.resistance(ser: ser20)
    }
    
    // Save record into user defaults
    
    @IBAction func save(_ sender: Any) {
        print("Saving!")
        
        // Save blank array if defaults is empty
        if (UserDefaults.standard.array(forKey: recordsID) == nil) {
            UserDefaults.standard.set([], forKey: recordsID)
        }
        
        recordsArray = UserDefaults.standard.array(forKey: recordsID)
        soilRecord = SoilDataRecord.init(recordSiteName: self.siteString, recordDate:  Date.init(), recordMoisture: moisture)
        
        let data = NSKeyedArchiver.archivedData(withRootObject: self.soilRecord!)
        recordsArray?.append(data)
        UserDefaults.standard.set(recordsArray, forKey: recordsID)
    }
    
    // ---------------------------
    
    // MARK: Table View Methods
    
    // ---------------------------
    
    // Set the number of sections in the table
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        if hasOpenedBefore() {
            return 1
        }
        
        else {
            return 0
        }
        
    }
    
    // Set the number of rows
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return 6
    }
    
    // Set the cell for each row
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        //avoid unwrapping optional
        if(self.temp == nil){
            self.temp = 0.0
        }
            
        // Switch depending on row
        
        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "tableViewHeader", for: indexPath)
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 44)
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SensorReadingCell", for: indexPath) as! SensorReadingsCell
            
            // Soil Moisture
            
            // from to 22 to 157
            
            cell.moistureLabel.text = moisture
            //cell.barWater.frame = CGRect.init(x: 0.5, y: 169 - (157-22) * (min(self.moistureNumber!, 100)/100), width: 154, height: 22 + (157-22) * (min(self.moistureNumber!, 100)/100))
            //cell.waveWater.center = CGPoint.init(x: 90.5, y: 152.5 + (157-22) * (min(self.moistureNumber!, 100)/100))
            
            cell.barWater.frame = CGRect.init(x: 0, y: cell.MoistureView.frame.height - (22 * cell.MoistureView.frame.width / 170), width: cell.MoistureView.frame.width , height: 22 * cell.MoistureView.frame.width / 170)
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: cell.barWater.bounds, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: 10.0, height: 10.0)).cgPath
            
            cell.barWater.layer.mask = maskLayer
            
            cell.waveWater.frame = CGRect.init(x: 0, y: cell.barWater.frame.minY - 27, width: cell.MoistureView.frame.width, height: 27 * cell.MoistureView.frame.width / 170)
            
            // Resistance
            
            if (resistance != invalid && resistance != " INF" && resistance != "") {
                let shortenedDouble = Double(resistance)!/1000
                self.resist = shortenedDouble
                cell.resistanceLabel.text = "\(String(format: "%0.1f",shortenedDouble)) kΩ"
                
            }
            else if resistance == " INF" {
                cell.resistanceLabel.text = "INF kΩ"
                self.resist = Double.greatestFiniteMagnitude
                cell.moistureLabel.text = "0%"
            }
            
            else {
                cell.resistanceLabel.text = invalid
                self.resist = 0
            }
            
            // Temperature
            
            cell.temperatureLabel.text = temperature
            cell.temperature = self.temp!
            
            cell.temperatureCelsiusLabel.text = invalid
            
            if cell.temperatureLabel.text != invalid {
                cell.temperatureCelsiusLabel.text = String(format: "%0.1f" , (self.temp! - 32)/1.8) + "℃"
                cell.temperatureBar.frame = CGRect.init(
                    x: Double(136 * cell.TemperatureView.frame.width / 170),
                    y: (Double(151 * cell.TemperatureView.frame.width / 170) - max(0, 90 * (self.temp!/100))),
                    width: Double(6.5 * (cell.TemperatureView.frame.width / 170)),
                    height: max(0, 90 * (self.temp!/100)))
            }
            
            else {
                cell.temperatureBar.frame = CGRect.init(x: Double(136 * cell.TemperatureView.frame.width / 170), y: 151 - max(0, 90 * (self.temp!/100)), width: 6.5, height: max(0, 90 * (self.temp!/100)))
            }

            // Date
            
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            cell.dateLabel.text = formatter.string(from: Date())
            formatter.dateFormat = "h:mm a"
            cell.timeLabel.text = formatter.string(from: Date())
            
            
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 355)
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "observationsHeader", for: indexPath)
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 44)
            return cell
        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "observationsCell", for: indexPath) as! ObservationsTableViewCell
            cell.setup(delegate: self)
            let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognizer:)))
            gestureRecognizer.delegate = self
            cell.PhotoView.addGestureRecognizer(gestureRecognizer)
            
            if image != nil {
                cell.photo.image = image
                cell.photo.layer.cornerRadius = 10.0
            }
            
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 230)
            return cell
        case 4:
            let cell = tableView.dequeueReusableCell(withIdentifier: "mapHeader", for: indexPath)
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 44)
            return cell
        case 5:
            let cell = tableView.dequeueReusableCell(withIdentifier: "mapCell", for: indexPath) as! MapTableViewCell
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 221)
            self.loadMap()
            //cell.mapView = mapView
            coordinateRegion = MKCoordinateRegionMakeWithDistance((locManager.location?.coordinate)!, 1000 * 2.0, 1000 * 2.0)
            cell.mapView.setRegion(coordinateRegion!, animated: false)
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SensorReadingCell", for: indexPath)
            cell.frame = CGRect(x: 0, y: 0, width: Int(self.view.frame.width), height: 355)
            return cell
        }
    }
    
    // Present image selector to user

    func handleTap(gestureRecognizer: UIGestureRecognizer) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .camera
            imagePicker.allowsEditing = false
            
            self.present(imagePicker, animated: true, completion: nil)
        }
    }
    
    // Scroll notes to correct page
    func handleNoteTap() {
        stopTimer()
        DataTable.scrollToRow(at: IndexPath(row: 2, section: 0), at: UITableViewScrollPosition.top, animated: true)
    }
    
    // Set height for each row
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        switch indexPath.row {
        case 0:
            return 44
        case 1:
            return 3 +  355 * self.view.frame.width / 375
        case 2:
            return 44
        case 3:
            return 230 * self.view.frame.width / 375
        case 4:
            return 44
        case 5:
            return 221
        default:
            return 44
        }
    }
    
    // Store the image from the image picker as the current image
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            self.image = image
            imageBool = true
            dismiss(animated: true, completion: nil)
            
            DataTable.reloadData()
        }
    }
    
    // If the weather getter comes back with data, set the temperature
    
    func didGetWeather(weather: Weather) {
        DispatchQueue.main.async() {
            self.temp = weather.tempFahrenheit
            self.DataTable.reloadData()
        }
    }
    
    // Print if there is an error with the weather getter

    func didNotGetWeather(error: NSError) {
        print("didNotGetWeather error: \(error)")
    }
    
    // Timer to refresh table
    func startTimer () {
        print("starting timer")
        shouldRefreshSensor = true
        timer =  Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(AddSoilRecordViewController.checkBluetooth), userInfo: nil, repeats: true)
    }
    
    func stopTimer() {
        print("stopping timer")
        shouldRefreshSensor = false
        timer?.invalidate()
        timer = nil
    }
    
    func didEndEditing() {
        startTimer()
    }
    
    // ---------------------------
    
    // MARK: Bluetooth Methods
    
    // ---------------------------
    
    // Check Bluetooth Connection
    
    func checkBluetooth() {
        
        // Bluetooth is not connected, present notification
        if nrfManagerInstance.connectionStatus == .disconnected {
            
            BluetoothView.center = CGPoint.init(x: self.view.frame.width/2, y: 1000)
            
            UIView.animate(withDuration: 1.0, animations: {
                self.view.bringSubview(toFront: self.BlurView)
                self.view.bringSubview(toFront: self.BluetoothView)
            })
            
            if (!pageOpened) {
                UIView.animate(withDuration: 0.75, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 3, options: UIViewAnimationOptions.curveEaseIn, animations:
                    {
                        self.BlurView.alpha = self.maxAlpha
                        self.BluetoothView.alpha = self.maxAlpha
                        self.BluetoothView.center = CGPoint.init(x: self.view.frame.width/2, y: self.view.frame.height/2)
                        
                }, completion:nil)
                pageOpened = true
            }
            
            else {
                self.BlurView.alpha = maxAlpha
                self.BluetoothView.alpha = maxAlpha
                self.BluetoothView.center = CGPoint.init(x: self.view.frame.width/2, y: self.view.frame.height/2)
            }
            
            
            if nrfManagerInstance.bluetoothOn == true {
                self.BluetoothImage.tintColor = UIColor.init(red: 48.0/255.0, green: 132/255.0, blue: 244/255.0, alpha: 1.0)
                UIView.animate(withDuration: 0.75, delay: 0.0, options:[UIViewAnimationOptions.repeat, UIViewAnimationOptions.curveEaseInOut, UIViewAnimationOptions.autoreverse], animations: {
                    
                    self.BluetoothImage.alpha = self.minAlpha
                    
                }, completion:nil)
                
                UIView.animate(withDuration: 0.3, delay: 0.0, options:[UIViewAnimationOptions.curveLinear], animations: {
                    
                    self.SettingsButton.isHidden = true
                    self.BluetoothText.center = CGPoint.init(x: 200, y: 95)
                    
                }, completion:nil)
                
                self.BluetoothText.text = "Scanning for Soil Moisture Sensor"
                getArduinoData()
            }
            
            else {
                
                UIView.animate(withDuration: 0.3, delay: 0.0, options:[UIViewAnimationOptions.curveLinear], animations: {
                    
                    self.BluetoothText.center = CGPoint.init(x: 200, y: 75)
                    self.SettingsButton.isHidden = false
                    
                }, completion:nil)
                
                self.BluetoothImage.layer.removeAllAnimations()
                self.BluetoothImage.alpha = maxAlpha
                self.BluetoothImage.tintColor = UIColor.lightGray
                self.BluetoothText.text = "Please Turn on Bluetooth in iOS Settings"
            }
        }
        
        // Bluetooth is connected, let user through.
        else if nrfManagerInstance.connectionStatus == .connected {
            
            UIView.animate(withDuration: 0.75, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 3, options: UIViewAnimationOptions.curveEaseIn, animations:
                {
                    self.BlurView.alpha = 0.0
                    self.BluetoothView.alpha = 0.0
                    self.BluetoothView.center = CGPoint.init(x: self.view.frame.width/2, y: 1000)
                    self.pageOpened = false
                    
            }, completion:{
                (result:Bool) in
                self.view.bringSubview(toFront: self.DataTable)
            })
        }
    }
    
    // If scanning, pulse the bluetooth image
    
    func animateBluetooth() {
        if nrfManagerInstance.connectionStatus == .disconnected && nrfManagerInstance.bluetoothOn == true {
            
            self.BluetoothImage.alpha = maxAlpha
            self.BluetoothImage.layer.removeAllAnimations()
            
            // Animation
            UIView.animate(withDuration: 0.75, delay: 0.0, options:[UIViewAnimationOptions.repeat, UIViewAnimationOptions.curveEaseInOut, UIViewAnimationOptions.autoreverse], animations: {
                
                // maxAlpha -> minAlpha and back
                self.BluetoothImage.alpha = self.minAlpha
                
            }, completion:nil)
        }
    }
    
    // Take user to iOS bluetooth settings
    @IBAction func bluetoothSettings(_ sender: Any) {
        UIApplication.shared.open(URL(string:"App-Prefs:root=Bluetooth")!, options: [:], completionHandler: nil)
    }
    
    // Can delete eventually if not sending any data to arduino
    func sendData()
    {
        // Example of sending data from phone to arduino
        let result = self.nrfManagerInstance.writeString("Hello, world!")
        print("result: %@", result)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

