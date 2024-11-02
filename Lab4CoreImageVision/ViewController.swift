import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    
    @IBOutlet weak var previewView: UIView?
    
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()
    
    var rootLayer: CALayer?
    var detectedHandRectangleShapeLayer: CAShapeLayer?
    
    private var detectionRequests: [VNDetectHumanHandPoseRequest]?
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("ViewDidLoad called, setting up camera and vision")
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            print("Metal is supported. Default device: \(metalDevice.name)")
        } else {
            print("Metal is not supported on this device.")
        }

        // Setup capture session
        self.session = self.setupAVCaptureSession()
        
        // Prepare Vision hand detection
        self.prepareVisionRequest()
        
        // Start camera session
        DispatchQueue.global(qos: .userInitiated).async {
            self.session?.startRunning()
        }
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
                let gesture = classifyHandGesture(wristPoint: wristPoint, indexTip: indexTip, middleTip: middleTip, ringTip: ringTip, pinkyTip: pinkyTip)
                print("Detected gesture: \(gesture ?? "Unknown")")
                
                // Display gesture classification result as a text overlay
                let textLayer = CATextLayer()
                textLayer.string = "Gesture: \(gesture ?? "Unknown")"
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

