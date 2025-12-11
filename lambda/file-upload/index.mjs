import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import crypto from "crypto";

// S3 Client configuration
const s3 = new S3Client({ region: "ap-southeast-1" });

// Supported MIME types with their extensions
const MIME_TYPE_MAP = {
  // Images
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/gif": "gif",
  "image/webp": "webp",
  "image/svg+xml": "svg",
  "image/bmp": "bmp",
  "image/tiff": "tiff",

  // Documents
  "application/pdf": "pdf",
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "application/vnd.ms-excel": "xls",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.ms-powerpoint": "ppt",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",

  // Text
  "text/plain": "txt",
  "text/html": "html",
  "text/css": "css",
  "text/javascript": "js",
  "text/csv": "csv",
  "text/markdown": "md",
  "text/x-markdown": "md",
  "application/json": "json",
  "application/xml": "xml",

  // Audio
  "audio/mpeg": "mp3",
  "audio/mp3": "mp3",
  "audio/wav": "wav",
  "audio/webm": "webm",
  "audio/ogg": "ogg",
  "audio/aac": "aac",
  "audio/flac": "flac",
  "audio/m4a": "m4a",

  // Video
  "video/mp4": "mp4",
  "video/mpeg": "mpeg",
  "video/webm": "webm",
  "video/ogg": "ogv",
  "video/quicktime": "mov",
  "video/x-msvideo": "avi",
  "video/x-matroska": "mkv",

  // Archives
  "application/zip": "zip",
  "application/x-rar-compressed": "rar",
  "application/x-7z-compressed": "7z",
  "application/x-tar": "tar",
  "application/gzip": "gz",
};

// Maximum file size (50MB in bytes)
const MAX_FILE_SIZE = 50 * 1024 * 1024;

/**
 * Get file extension from MIME type
 */
function getExtensionFromMimeType(mimeType) {
  if (!mimeType) return "bin";

  const extension = MIME_TYPE_MAP[mimeType.toLowerCase()];
  if (extension) return extension;

  // Try to extract from mime type (e.g., "image/png" -> "png")
  const parts = mimeType.split("/");
  if (parts.length === 2) {
    return parts[1].split(";")[0];
  }

  return "bin";
}

/**
 * Validate request parameters
 */
function validateRequest(event) {
  const errors = [];

  // Parse body if it's a string
  let body = event.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch (e) {
      errors.push("Invalid JSON body");
      return { isValid: false, errors, body: null };
    }
  }

  // Validate content type
  if (!body.contentType) {
    errors.push("contentType is required");
  } else if (typeof body.contentType !== "string") {
    errors.push("contentType must be a string");
  }

  // Validate file size if provided
  if (body.fileSize) {
    const size = parseInt(body.fileSize);
    if (isNaN(size)) {
      errors.push("fileSize must be a number");
    } else if (size <= 0) {
      errors.push("fileSize must be greater than 0");
    } else if (size > MAX_FILE_SIZE) {
      errors.push(`fileSize must not exceed ${MAX_FILE_SIZE / 1024 / 1024}MB`);
    }
  }

  // Validate custom filename if provided
  if (body.fileName && typeof body.fileName !== "string") {
    errors.push("fileName must be a string");
  }

  return {
    isValid: errors.length === 0,
    errors,
    body: body || {}
  };
}

/**
 * Generate unique filename
 */
function generateFileName(contentType, customFileName = null) {
  const extension = getExtensionFromMimeType(contentType);

  if (customFileName) {
    // Sanitize custom filename
    const sanitized = customFileName
      .replace(/[^a-zA-Z0-9._-]/g, "_")
      .substring(0, 100);

    // Add UUID prefix to ensure uniqueness
    const uuid = crypto.randomUUID().split("-")[0];
    return `${uuid}_${sanitized}`;
  }

  // Generate random UUID filename
  return `${crypto.randomUUID()}.${extension}`;
}

/**
 * Lambda handler
 */
export const handler = async (event) => {
  try {
    console.log("Event received:", JSON.stringify(event, null, 2));

    // Validate request
    const validation = validateRequest(event);
    if (!validation.isValid) {
      return {
        statusCode: 400,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type,Authorization",
          "Access-Control-Allow-Methods": "POST,OPTIONS"
        },
        body: JSON.stringify({
          error: "Validation failed",
          details: validation.errors
        })
      };
    }

    const { contentType, fileSize, fileName: customFileName } = validation.body;
    const bucket = process.env.S3_BUCKET_NAME;

    if (!bucket) {
      throw new Error("S3_BUCKET_NAME environment variable is not set");
    }

    // Generate filename
    const fileName = generateFileName(contentType, customFileName);

    // Create S3 PutObject command
    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: fileName,
      ContentType: contentType,
      // Optional metadata
      Metadata: {
        "upload-timestamp": new Date().toISOString(),
        "original-filename": customFileName || fileName
      }
    });

    // Generate pre-signed URL (5 minutes expiration)
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

    // Generate the public URL (without query parameters)
    const publicUrl = `https://${bucket}.s3.ap-southeast-1.amazonaws.com/${fileName}`;

    console.log("Upload URL generated successfully:", { fileName, contentType });

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "POST,OPTIONS"
      },
      body: JSON.stringify({
        success: true,
        uploadUrl,
        publicUrl,
        key: fileName,
        expiresIn: 300,
        metadata: {
          contentType,
          fileSize: fileSize || null,
          bucket
        }
      })
    };

  } catch (error) {
    console.error("Error:", error);

    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "POST,OPTIONS"
      },
      body: JSON.stringify({
        error: "Internal server error",
        message: error.message
      })
    };
  }
};
