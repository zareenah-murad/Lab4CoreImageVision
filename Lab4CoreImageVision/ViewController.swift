import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    
    @IBOutlet weak var previewView: UIView?
    var countdownLabel: UILabel!
    var resultLabel: UILabel!
    var pointMessageLabel: UILabel!
    var audioPlayer: AVAudioPlayer?
    
    // New properties for best of three functionality
    var userScore = 0
    var cpuScore = 0
    var roundNumber = 1
    var userScoreLabel: UILabel!
    var cpuScoreLabel: UILabel!
    var roundLabel: UILabel!
    var playAgainButton: UIButton!
    
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()
    
    var rootLayer: CALayer?
    var detectedHandRectangleShapeLayer: CAShapeLayer?
    
    private var detectionRequests: [VNDetectHumanHandPoseRequest]?
    private var userGesture: String? // Variable to store the detected hand gesture
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Existing setup code
        print("ViewDidLoad called, setting up camera and vision")
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            print("Metal is supported. Default device: \(metalDevice.name)")
        } else {
            print("Metal is not supported on this device.")
        }

        // Setup labels on top of previewView
        setupLabels()
        setupScoreAndRoundLabels() // New function to set up score and round labels
        setupPointMessageLabel()
        
        // Setup capture session
        self.session = self.setupAVCaptureSession()
        
        // Prepare Vision hand detection
        self.prepareVisionRequest()
        
        // Start camera session
        DispatchQueue.global(qos: .userInitiated).async {
            self.session?.startRunning()
            DispatchQueue.main.async {
                self.startCountdown()
            }
        }
        
        playBackgroundMusic()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopBackgroundMusic() // Stop music when navigating away
    }
    
    func playBackgroundMusic() {
        // Load the background music file
        guard let musicURL = Bundle.main.url(forResource: "Powerful-Trap-(chosic.com)", withExtension: "mp3") else {
            print("Music file not found.")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: musicURL)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.2 // Lower volume (range is 0.0 to 1.0)
            audioPlayer?.play()
        } catch {
            print("Error playing background music: \(error.localizedDescription)")
        }
    }

    func stopBackgroundMusic() {
        audioPlayer?.stop()
    }
    
    // MARK: Setup Labels
    func setupLabels() {
        // Configure countdownLabel
        countdownLabel = UILabel()
        countdownLabel.textAlignment = .center
        countdownLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        countdownLabel.textColor = .white
        countdownLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        countdownLabel.isHidden = true
        countdownLabel.layer.cornerRadius = 10
        countdownLabel.layer.masksToBounds = true
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countdownLabel) // Add to main view, so it layers above previewView
        
        // Configure resultLabel
        resultLabel = UILabel()
        resultLabel.textAlignment = .center
        resultLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        resultLabel.textColor = .yellow
        resultLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        resultLabel.isHidden = true
        resultLabel.layer.cornerRadius = 10
        resultLabel.layer.masksToBounds = true
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultLabel) // Add to main view, so it layers above previewView
        
        // Add constraints for countdownLabel (top center of previewView)
        NSLayoutConstraint.activate([
            countdownLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60), // Increased from 20 to 60 to move lower
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.widthAnchor.constraint(equalToConstant: 200),
            countdownLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Add constraints for resultLabel (bottom center of previewView)
        NSLayoutConstraint.activate([
            resultLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60), // Decreased from -20 to -60 to move higher
            resultLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resultLabel.widthAnchor.constraint(equalToConstant: 250),
            resultLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    
    // MARK: Setup Score and Round Labels
    func setupScoreAndRoundLabels() {
        // Round label (Top Left)
        roundLabel = UILabel()
        roundLabel.textAlignment = .left
        roundLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        roundLabel.textColor = .white
        roundLabel.text = "Round: \(roundNumber)"
        roundLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(roundLabel)
        
        // CPU score label (Top Right)
        cpuScoreLabel = UILabel()
        cpuScoreLabel.textAlignment = .right
        cpuScoreLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        cpuScoreLabel.textColor = .white
        cpuScoreLabel.text = "CPU: \(cpuScore)"
        cpuScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cpuScoreLabel)
        
        // User score label (Bottom Right)
        userScoreLabel = UILabel()
        userScoreLabel.textAlignment = .right
        userScoreLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        userScoreLabel.textColor = .white
        userScoreLabel.text = "User: \(userScore)"
        userScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userScoreLabel)
        
        // Constraints
        NSLayoutConstraint.activate([
            roundLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            roundLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            cpuScoreLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            cpuScoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            userScoreLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            userScoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    // MARK: Setup Point Message Label
    func setupPointMessageLabel() {
        pointMessageLabel = UILabel()
        pointMessageLabel.textAlignment = .center
        pointMessageLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        pointMessageLabel.textColor = .white
        pointMessageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        pointMessageLabel.layer.cornerRadius = 10
        pointMessageLabel.layer.masksToBounds = true
        pointMessageLabel.isHidden = true
        pointMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pointMessageLabel)
        
        // Center the label in the middle of the screen
        NSLayoutConstraint.activate([
            pointMessageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pointMessageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pointMessageLabel.widthAnchor.constraint(equalToConstant: 200),
            pointMessageLabel.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Start Countdown
    func startCountdown() {
        countdownLabel.isHidden = false
        let countdownSteps = ["Rock ✊", "Paper 🤚", "Scissors ✌️", "Shoot!"]
        
        for (index, step) in countdownSteps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index)) { [weak self] in
                guard let self = self else { return }
                
                print("Countdown step: \(step)")
                self.countdownLabel.text = step
                
                if step == "Shoot!" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.detectUserChoice()
                    }
                }
            }
        }
    }
    
    // MARK: Detect User Choice and Display Results
    fileprivate func detectUserChoice() {
        let gesture = userGesture ?? "Unknown"
        let cpuChoice = randomCPUChoice()
        
        DispatchQueue.main.async {
            self.resultLabel.isHidden = false
            self.resultLabel.text = "User: \(gesture)  |  CPU: \(cpuChoice)"
            self.countdownLabel.isHidden = true
            
            self.updateScores(userChoice: gesture, cpuChoice: cpuChoice)
        }
    }
    
    // MARK: Show Point Message
    func showPointMessage(for scorer: String?) {
        // Determine the message based on the scorer
        if let scorer = scorer {
            pointMessageLabel.text = "+1 point for \(scorer)"
        } else {
            pointMessageLabel.text = "Draw, no points"
        }
        
        // Make the label visible and animate it to fade in and out
        pointMessageLabel.alpha = 0
        pointMessageLabel.isHidden = false
        UIView.animate(withDuration: 0.5, animations: {
            self.pointMessageLabel.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 0.5, options: [], animations: {
                self.pointMessageLabel.alpha = 0.0
            }) { _ in
                self.pointMessageLabel.isHidden = true
            }
        }
    }

    // Update the `updateScores` function to use `showPointMessage`
    fileprivate func updateScores(userChoice: String, cpuChoice: String) {
        var scorer: String? = nil
        
        if (userChoice == "Rock" && cpuChoice == "Scissors") ||
            (userChoice == "Scissors" && cpuChoice == "Paper") ||
            (userChoice == "Paper" && cpuChoice == "Rock") {
            userScore += 1
            scorer = "User"
        } else if (cpuChoice == "Rock" && userChoice == "Scissors") ||
                    (cpuChoice == "Scissors" && userChoice == "Paper") ||
                    (cpuChoice == "Paper" && userChoice == "Rock") {
            cpuScore += 1
            scorer = "CPU"
        }
        
        // Show the point message
        showPointMessage(for: scorer)
        
        // Update labels
        cpuScoreLabel.text = "CPU: \(cpuScore)"
        userScoreLabel.text = "User: \(userScore)"
        
        if userScore >= 2 || cpuScore >= 2 {
            if userScore > cpuScore {
                showEndGame(winner: "User")
            } else {
                showEndGame(winner: "CPU")
            }
        } else {
            // Move to the next round
            roundNumber += 1
            roundLabel.text = "Round: \(roundNumber)"
            startCountdown()
        }
    }
    
    // MARK: Show End Game
    fileprivate func showEndGame(winner: String) {
        resultLabel.text = "\(winner) wins the game!"
        
        // Display "Play Again" button with new styling
        playAgainButton = UIButton(type: .system)
        playAgainButton.setTitle("Play Again", for: .normal)
        playAgainButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        playAgainButton.backgroundColor = UIColor.yellow.withAlphaComponent(0.8) // Slightly transparent yellow background
        playAgainButton.setTitleColor(.black, for: .normal)
        playAgainButton.layer.cornerRadius = 12
        playAgainButton.translatesAutoresizingMaskIntoConstraints = false
        playAgainButton.addTarget(self, action: #selector(resetGame), for: .touchUpInside)
        view.addSubview(playAgainButton)
        
        // Add constraints for playAgainButton to make it larger and center it
        NSLayoutConstraint.activate([
            playAgainButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playAgainButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playAgainButton.widthAnchor.constraint(equalToConstant: 180),
            playAgainButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    
    // MARK: Reset Game
    @objc fileprivate func resetGame() {
        // Reset scores and round number
        userScore = 0
        cpuScore = 0
        roundNumber = 1
        
        // Update labels
        userScoreLabel.text = "User: \(userScore)"
        cpuScoreLabel.text = "CPU: \(cpuScore)"
        roundLabel.text = "Round: \(roundNumber)"
        resultLabel.isHidden = true
        
        // Hide the play again button
        playAgainButton.removeFromSuperview()
        
        // Start the first round again
        startCountdown()
        
        playBackgroundMusic() // Play music when resetting game
    }

    // MARK: Random CPU Choice Generator
    fileprivate func randomCPUChoice() -> String {
        let choices = ["Rock", "Paper", "Scissors"]
        return choices.randomElement() ?? "Rock"
    }
    
    // MARK: Vision Hand Detection Setup
    fileprivate func prepareVisionRequest() {
        let handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest.maximumHandCount = 1
        self.detectionRequests = [handPoseRequest]
        
        self.setupVisionDrawingLayers()
    }
    
    // MARK: Camera Setup
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        do {
            let inputDevice = try self.configureFrontCamera(for: captureSession)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            self.designatePreviewLayer(for: captureSession)
            return captureSession
        } catch let executionError as NSError {
            print("Failed with error \(executionError.code): \(executionError.localizedDescription)")
        } catch {
            print("An unexpected failure has occurred")
        }
        return nil
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    return (device, highestResolution.resolution)
                }
            }
        }
        throw NSError(domain: "ViewController", code: 1, userInfo: nil)
    }
    
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        for format in device.formats {
            let deviceFormatDescription = format.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = format
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        if let highestResolutionFormat = highestResolutionFormat {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat, resolution)
        }
        return nil
    }
    
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue
        self.captureDevice = inputDevice
        self.captureDeviceResolution = resolution
    }
    
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer = videoPreviewLayer
        videoPreviewLayer.videoGravity = .resizeAspectFill
        if let previewRootLayer = self.previewView?.layer {
            self.rootLayer = previewRootLayer
            videoPreviewLayer.frame = previewRootLayer.bounds
            previewRootLayer.addSublayer(videoPreviewLayer)
        }
    }
    
    // MARK: Vision Drawing
    fileprivate func setupVisionDrawingLayers() {
        guard let rootLayer = self.rootLayer else {
            print("Root layer is not initialized.")
            return
        }

        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(overlayLayer)

        let handRectangleShapeLayer = CAShapeLayer()
        handRectangleShapeLayer.name = "HandRectangleOutlineLayer"
        handRectangleShapeLayer.strokeColor = UIColor.green.cgColor
        handRectangleShapeLayer.lineWidth = 2.0
        handRectangleShapeLayer.fillColor = UIColor.clear.cgColor

        overlayLayer.addSublayer(handRectangleShapeLayer)
        
        self.detectedHandRectangleShapeLayer = handRectangleShapeLayer
        print("Vision drawing layers set up successfully")
    }
    
    // MARK: Update Hand Overlay
    fileprivate func updateHandOverlay(observations: [VNHumanHandPoseObservation]) {
        guard let handRectangleShapeLayer = self.detectedHandRectangleShapeLayer else {
            print("Detected hand rectangle shape layer not initialized")
            return
        }
        
        let handPath = CGMutablePath()
        self.detectedHandRectangleShapeLayer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        print("Received \(observations.count) observations")

        for hand in observations {
            do {
                // Retrieve points for the wrist, index finger, and pinky finger
                let wristPoint = try hand.recognizedPoint(.wrist)
                let indexTip = try hand.recognizedPoint(.indexTip)
                let pinkyTip = try hand.recognizedPoint(.littleTip)
                let middleTip = try hand.recognizedPoint(.middleTip)
                let ringTip = try hand.recognizedPoint(.ringTip)

                print("Wrist point: \(wristPoint), Index tip: \(indexTip), Pinky tip: \(pinkyTip)")

                guard wristPoint.confidence > 0.3, indexTip.confidence > 0.3, pinkyTip.confidence > 0.3 else {
                    print("Low confidence in detected points, skipping")
                    continue
                }

                let wristPosition = CGPoint(x: wristPoint.location.x * view.bounds.width, y: (1 - wristPoint.location.y) * view.bounds.height)
                let indexPosition = CGPoint(x: indexTip.location.x * view.bounds.width, y: (1 - indexTip.location.y) * view.bounds.height)
                let pinkyPosition = CGPoint(x: pinkyTip.location.x * view.bounds.width, y: (1 - pinkyTip.location.y) * view.bounds.height)

                // Draw circles on wrist, index, and pinky points
                addCircle(at: wristPosition, color: UIColor.red, radius: 5, label: "Wrist: \(String(format: "%.2f", wristPoint.confidence))")
                addCircle(at: indexPosition, color: UIColor.blue, radius: 5, label: "Index: \(String(format: "%.2f", indexTip.confidence))")
                addCircle(at: pinkyPosition, color: UIColor.green, radius: 5, label: "Pinky: \(String(format: "%.2f", pinkyTip.confidence))")

                // Calculate and draw bounding box
                let minX = min(wristPosition.x, indexPosition.x, pinkyPosition.x)
                let minY = min(wristPosition.y, indexPosition.y, pinkyPosition.y)
                let maxX = max(wristPosition.x, indexPosition.x, pinkyPosition.x)
                let maxY = max(wristPosition.y, indexPosition.y, pinkyPosition.y)
                
                let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                print("Calculated bounding box: \(boundingBox)")
                handPath.addRect(boundingBox)
                
                // Gesture classification
                userGesture = classifyHandGesture(wristPoint: wristPoint, indexTip: indexTip, middleTip: middleTip, ringTip: ringTip, pinkyTip: pinkyTip)
                print("Detected gesture: \(userGesture ?? "Unknown")")
                
                // Display gesture classification result as a text overlay
                let textLayer = CATextLayer()
                textLayer.string = "Gesture: \(userGesture ?? "Unknown")"
                textLayer.fontSize = 18
                textLayer.foregroundColor = UIColor.yellow.cgColor
                textLayer.position = CGPoint(x: self.view.bounds.midX, y: 40)
                textLayer.alignmentMode = .center
                textLayer.bounds = CGRect(x: 0, y: 0, width: 200, height: 30)
                self.detectedHandRectangleShapeLayer?.addSublayer(textLayer)
                
            } catch {
                print("Error retrieving hand points: \(error)")
            }
        }

        DispatchQueue.main.async {
            handRectangleShapeLayer.path = handPath
            print("Bounding box path updated")
        }
    }
    
    // Helper function to classify the current gesture
    fileprivate func classifyHandGesture(wristPoint: VNRecognizedPoint, indexTip: VNRecognizedPoint, middleTip: VNRecognizedPoint, ringTip: VNRecognizedPoint, pinkyTip: VNRecognizedPoint) -> String? {
        // Calculate distances from wrist to each fingertip
        let indexDistance = distance(from: wristPoint.location, to: indexTip.location)
        let middleDistance = distance(from: wristPoint.location, to: middleTip.location)
        let ringDistance = distance(from: wristPoint.location, to: ringTip.location)
        let pinkyDistance = distance(from: wristPoint.location, to: pinkyTip.location)
        
        // Print out the distances for debugging
        print("Debugging Distances - Index: \(indexDistance), Middle: \(middleDistance), Ring: \(ringDistance), Pinky: \(pinkyDistance)")
        
        // Heuristics for Rock, Paper, Scissors
        if indexDistance < 0.2 && middleDistance < 0.2 && ringDistance < 0.2 && pinkyDistance < 0.2 {
            print("Detected Gesture: Rock")
            return "Rock" // All fingers close to the palm
        } else if indexDistance > 0.25 && middleDistance > 0.25 && ringDistance > 0.25 && pinkyDistance > 0.25 {
            print("Detected Gesture: Paper")
            return "Paper" // All fingers extended (or mostly extended)
        } else if indexDistance > 0.3 && middleDistance > 0.3 && ringDistance < 0.25 && pinkyDistance < 0.25 {
            print("Detected Gesture: Scissors")
            return "Scissors" // Index and middle extended, ring and pinky curled
        }
        
        print("Detected Gesture: Unknown")
        return "Unknown"
    }

    // Helper function to calculate the distance between two points
    fileprivate func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        return sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
    }

    // Helper function to add circles and labels at specific points
    fileprivate func addCircle(at point: CGPoint, color: UIColor, radius: CGFloat, label: String) {
        let circleLayer = CAShapeLayer()
        let circlePath = UIBezierPath(arcCenter: point, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
        
        circleLayer.path = circlePath.cgPath
        circleLayer.fillColor = color.cgColor
        self.detectedHandRectangleShapeLayer?.addSublayer(circleLayer)
        
        // Create a text layer for confidence score
        let textLayer = CATextLayer()
        textLayer.string = label
        textLayer.fontSize = 12
        textLayer.foregroundColor = color.cgColor
        textLayer.position = CGPoint(x: point.x, y: point.y - 15) // Position slightly above the point
        textLayer.alignmentMode = .center
        textLayer.bounds = CGRect(x: 0, y: 0, width: 60, height: 20)
        
        self.detectedHandRectangleShapeLayer?.addSublayer(textLayer)
    }

    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("captureOutput called - Frame captured")
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain image buffer")
            return
        }
        
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        
        do {
            print("Performing hand pose detection")
            try imageRequestHandler.perform(self.detectionRequests ?? [])
            if let request = self.detectionRequests?.first as? VNDetectHumanHandPoseRequest,
               let observations = request.results as? [VNHumanHandPoseObservation] {
                self.updateHandOverlay(observations: observations)
            }
        } catch let error as NSError {
            print("Failed to perform hand pose detection: \(error)")
        }
    }

    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            return .rightMirrored
        case .landscapeLeft:
            return .downMirrored
        case .landscapeRight:
            return .upMirrored
        default:
            return .leftMirrored
        }
    }
}

