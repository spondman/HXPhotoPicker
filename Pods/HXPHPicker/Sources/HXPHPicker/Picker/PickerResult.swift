//
//  PickerResult.swift
//  HXPHPicker
//
//  Created by Slience on 2021/3/8.
//

import UIKit
import AVFoundation

public struct PickerResult {
    
    /// 已选的资源
    /// getURLs 获取原始资源的URL
    public let photoAssets: [PhotoAsset]
    
    /// 是否选择的原图
    public let isOriginal: Bool
    
    /// 初始化
    /// - Parameters:
    ///   - photoAssets: 对应 PhotoAsset 数据的数组
    ///   - isOriginal: 是否原图
    public init(
        photoAssets: [PhotoAsset],
        isOriginal: Bool
    ) {
        self.photoAssets = photoAssets
        self.isOriginal = isOriginal
    }
}

// MARK: Get Image / Video URL
public extension PickerResult {
    
    /// 获取 image
    /// - Parameters:
    ///   - compressionScale: 压缩比例，获取系统相册里的资源时有效
    ///   - imageHandler: 每一次获取image都会触发
    ///   - completionHandler: 全部获取完成(失败的不会添加)
    func getImage(
        compressionScale: CGFloat = 0.5,
        imageHandler: ((UIImage?, PhotoAsset, Int) -> Void)? = nil,
        completionHandler: @escaping ([UIImage]) -> Void
    ) {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hxphpicker.get.image")
        var images: [UIImage] = []
        for (index, photoAsset) in photoAssets.enumerated() {
            queue.async(
                group: group,
                execute: DispatchWorkItem(block: {
                    let semaphore = DispatchSemaphore(value: 0)
                    photoAsset.requestImage(compressionScale: compressionScale) { image, phAsset in
                        imageHandler?(image, phAsset, index)
                        if let image = image {
                            images.append(image)
                        }
                        semaphore.signal()
                    }
                    semaphore.wait()
                })
            )
        }
        group.notify(queue: .main) {
            completionHandler(images)
        }
    }
    
    /// 获取视频地址
    /// - Parameters:
    ///   - exportPreset: 视频分辨率，默认ratio_640x480
    ///   - videoQuality: 视频质量[0-10]，默认4
    ///   - exportSession: 导出视频时对应的 AVAssetExportSession   
    ///   - videoURLHandler: 每一次获取视频地址都会触发
    ///   - completionHandler: 全部获取完成(失败的不会添加)
    func getVideoURL(
        exportPreset: ExportPreset = .ratio_640x480,
        videoQuality: Int = 4,
        exportSession: ((AVAssetExportSession, PhotoAsset, Int) -> Void)? = nil,
        videoURLHandler: ((Result<AssetURLResult, AssetError>, PhotoAsset, Int) -> Void)? = nil,
        completionHandler: @escaping ([URL]) -> Void
    ) {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hxphpicker.get.videoURL")
        var videoURLs: [URL] = []
        for (index, photoAsset) in photoAssets.enumerated() {
            queue.async(
                group: group,
                execute: DispatchWorkItem(block: {
                    let semaphore = DispatchSemaphore(value: 0)
                    photoAsset.getVideoURL(
                        exportPreset: exportPreset,
                        videoQuality: videoQuality,
                        exportSession: { session in
                            exportSession?(session, photoAsset, index)
                        }
                    ) { result in
                        switch result {
                        case .success(let response):
                            videoURLs.append(response.url)
                        case .failure(_):
                            break
                        }
                        videoURLHandler?(result, photoAsset, index)
                        semaphore.signal()
                    }
                    semaphore.wait()
                })
            )
        }
        group.notify(queue: .main) {
            completionHandler(videoURLs)
        }
    }
}

// MARK: Get Original URL
public extension PickerResult {
    
    /// 获取已选资源的地址（原图）
    /// 不包括网络资源，如果网络资源编辑过则会获取
    /// - Parameters:
    ///   - options: 获取的类型
    ///   - completion: result
    func getURLs(
        options: Options = .any,
        completion: @escaping ([URL]) -> Void
    ) {
        var urls: [URL] = []
        getURLs(
            options: options
        ) { result, photoAsset, index in
            switch result {
            case .success(let response):
                if response.urlType == .local {
                    urls.append(response.url)
                }
            case .failure(_):
                break
            }
        } completionHandler: { _ in
            completion(urls)
        }
    }
    
    /// 获取已选资源的地址（原图）
    /// 包括网络图片
    /// - Parameters:
    ///   - options: 获取的类型
    ///   - handler: 获取到url的回调
    ///   - completionHandler: 全部获取完成
    func getURLs(
        options: Options = .any,
        urlReceivedHandler handler: (
            (Result<AssetURLResult, AssetError>, PhotoAsset, Int) -> Void
        )? = nil,
        completionHandler: @escaping ([URL]) -> Void
    ) {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hxphpicker.request.urls")
        var urls: [URL] = []
        for (index, photoAsset) in photoAssets.enumerated() {
            queue.async(
                group: group,
                execute: DispatchWorkItem.init(block: {
                    let semaphore = DispatchSemaphore(value: 0)
                    var mediatype: PhotoAsset.MediaType = .photo
                    if options.contains([.photo, .video]) {
                        mediatype = photoAsset.mediaType
                    }else if options.contains([.photo]) {
                        mediatype = .photo
                    }else if options.contains([.video]) {
                        mediatype = .video
                    }
                    #if HXPICKER_ENABLE_EDITOR
                    if photoAsset.mediaSubType == .livePhoto &&
                        photoAsset.photoEdit != nil {
                        mediatype = .photo
                    }
                    #endif
                    let resultHandler: PhotoAsset.AssetURLCompletion = { result in
                        switch result {
                        case .success(let respone):
                            urls.append(respone.url)
                        case .failure(_):
                            break
                        }
                        handler?(result, photoAsset, index)
                        semaphore.signal()
                    }
                    if mediatype == .photo {
                        if photoAsset.mediaSubType == .livePhoto {
                            photoAsset.getLivePhotoURL { result in
                                resultHandler(result)
                            }
                        }else {
                            photoAsset.getImageURL { result in
                                resultHandler(result)
                            }
                        }
                    }else {
                        photoAsset.getVideoURL { result in
                            resultHandler(result)
                        }
                    }
                    semaphore.wait()
                })
            )
        }
        group.notify(queue: .main) {
            completionHandler(urls)
        }
    }
}
