//
//  ViewController.swift
//  Camera POC
//
//  Created by Ibrahim Baisa on 30/07/24.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController {
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var zoomSlider: UISlider!
    @IBOutlet weak var contrastSlider: UISlider!
    @IBOutlet weak var flashSwitch: UISwitch!

    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var captureDevice: AVCaptureDevice?
    var photoOutput: AVCapturePhotoOutput?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCameraSession()
        setupSliders()
        setupFlashSwitch()
        setupPinchGesture()
        requestPhotoLibraryAuthorization()
    }

    // Setup the camera session
    func setupCameraSession() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.beginConfiguration()
        
        // Set up the capture device
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        self.captureDevice = captureDevice
        
        // Set up the input for the capture device
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Error setting up camera input: \(error)")
            return
        }
        
        // Set up the photo output
        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        // Set up the preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let videoPreviewLayer = videoPreviewLayer else { return }
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = previewView.layer.bounds
        previewView.layer.addSublayer(videoPreviewLayer)
        
        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    // Setup the zoom and contrast sliders
    func setupSliders() {
        zoomSlider.minimumValue = 0.0
        zoomSlider.maximumValue = 1.0

        contrastSlider.minimumValue = 0.0
        contrastSlider.maximumValue = 1.0
    }

    // Setup the flash switch
    func setupFlashSwitch() {
        flashSwitch.isOn = false
    }

    // Setup the pinch gesture for zoom
    func setupPinchGesture() {
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewView.addGestureRecognizer(pinchGestureRecognizer)
    }

    // Request authorization to access the photo library
    func requestPhotoLibraryAuthorization() {
        PHPhotoLibrary.requestAuthorization { status in
            if status != .authorized {
                print("Photo library access denied")
            }
        }
    }

    // Handle pinch gesture to zoom
    @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }

        if pinch.state == .changed {
            let maxZoomFactor = device.activeFormat.videoMaxZoomFactor
            let minZoomFactor: CGFloat = 1.0
            var zoomFactor = device.videoZoomFactor * pinch.scale
            zoomFactor = min(max(zoomFactor, minZoomFactor), maxZoomFactor)

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoomFactor
                device.unlockForConfiguration()
                
                // Update zoom slider value
                zoomSlider.value = Float((zoomFactor - minZoomFactor) / (maxZoomFactor - minZoomFactor))
            } catch {
                print("Error locking configuration: \(error)")
            }
            
            pinch.scale = 1.0
        }
    }

    // Update camera zoom based on zoom slider value
    @IBAction func zoomSliderChanged(_ sender: UISlider) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            let maxZoomFactor = device.activeFormat.videoMaxZoomFactor
            let zoomFactor = CGFloat(sender.value) * (maxZoomFactor - 1.0) + 1.0
            device.videoZoomFactor = max(1.0, min(zoomFactor, maxZoomFactor))
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error)")
        }
    }

    // Update camera contrast based on contrast slider value
    @IBAction func contrastSliderChanged(_ sender: UISlider) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            let minValue = device.minExposureTargetBias
            let maxValue = device.maxExposureTargetBias
            let contrastValue = sender.value * (maxValue - minValue) + minValue
            device.setExposureTargetBias(max(minValue, min(contrastValue, maxValue)), completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Error setting contrast: \(error)")
        }
    }

    // Take a photo and handle the flash setting
    @IBAction func takePhoto(_ sender: UIButton) {
        guard let photoOutput = photoOutput else { return }
        
        let flashMode: AVCaptureDevice.FlashMode = flashSwitch.isOn ? .on : .off
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // Save the taken photo to the gallery
    func savePhotoToGallery(_ image: UIImage) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let filename = "photo_\(dateString).jpg"
        
        PHPhotoLibrary.shared().performChanges({
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", "POC")
            let fetchedAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
            var album: PHAssetCollection?
            if fetchedAlbums.count == 0 {
                // Create a new album if it does not exist
                var albumPlaceholder: PHObjectPlaceholder?
                let albumChangeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "POC")
                albumPlaceholder = albumChangeRequest.placeholderForCreatedAssetCollection
                
                // Create the photo asset
                let assetChangeRequest = PHAssetCreationRequest.forAsset()
                if let imageData = image.jpegData(compressionQuality: 1.0) {
                    assetChangeRequest.addResource(with: .photo, data: imageData, options: nil)
                }
                
                // Add the photo asset to the new album
                if let albumPlaceholder = albumPlaceholder {
                    let albumFetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumPlaceholder.localIdentifier], options: nil)
                    album = albumFetchResult.firstObject
                    if let album = album {
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                        albumChangeRequest?.addAssets([assetChangeRequest.placeholderForCreatedAsset] as NSArray)
                    }
                }
            } else {
                // Use the existing album
                album = fetchedAlbums.firstObject
                let assetChangeRequest = PHAssetCreationRequest.forAsset()
                if let imageData = image.jpegData(compressionQuality: 1.0) {
                    assetChangeRequest.addResource(with: .photo, data: imageData, options: nil)
                }
                
                if let album = album {
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetChangeRequest.placeholderForCreatedAsset] as NSArray)
                }
            }
        }) { success, error in
            if success {
                print("Photo saved successfully as \(filename)")
            } else {
                print("Error saving photo: \(String(describing: error))")
            }
        }
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    // Handle the captured photo
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("Error: Photo data representation is nil")
            return
        }
        
        if let image = UIImage(data: imageData) {
            savePhotoToGallery(image)
        } else {
            print("Error: Could not create UIImage from data")
        }
    }
}
