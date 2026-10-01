package com.documentstudio.document_studio

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "document_studio/saf"
    private val pickFolderRequest = 0x51AF
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPersistableFolder" -> {
                        if (pendingFolderResult != null) {
                            result.error("busy", "Folder picker already open", null)
                            return@setMethodCallHandler
                        }
                        pendingFolderResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                            )
                        }
                        startActivityForResult(intent, pickFolderRequest)
                    }
                    "listPdfsInFolder" -> {
                        val uriStr = call.argument<String>("uri")
                        if (uriStr.isNullOrBlank()) {
                            result.success(emptyList<Map<String, String>>())
                            return@setMethodCallHandler
                        }
                        result.success(listPdfs(Uri.parse(uriStr)))
                    }
                    "copyContentUriToCache" -> {
                        val uriStr = call.argument<String>("uri")
                        val name = call.argument<String>("name") ?: "document.pdf"
                        if (uriStr.isNullOrBlank()) {
                            result.error("bad_args", "Missing uri", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val path = copyUriToCache(Uri.parse(uriStr), name)
                            result.success(mapOf("path" to path))
                        } catch (e: Exception) {
                            result.error("copy_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFolderRequest) return
        val pending = pendingFolderResult
        pendingFolderResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        val treeUri = data.data!!
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(treeUri, flags)
        } catch (_: SecurityException) {
            // Some providers only allow read; try read-only.
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                pending.error("permission", "Could not persist folder access", null)
                return
            }
        }
        val name = DocumentsContract.getTreeDocumentId(treeUri)
            ?.substringAfterLast(':')
            ?.substringAfterLast('/')
            ?.ifBlank { null }
            ?: "Granted folder"
        pending.success(mapOf("uri" to treeUri.toString(), "name" to name))
    }

    private fun listPdfs(treeUri: Uri): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val docId = if (idIdx >= 0) cursor.getString(idIdx) else continue
                val name = if (nameIdx >= 0) cursor.getString(nameIdx) else "document.pdf"
                val mime = if (mimeIdx >= 0) cursor.getString(mimeIdx) else ""
                val isPdf = mime == "application/pdf" ||
                    name?.lowercase()?.endsWith(".pdf") == true
                if (!isPdf) continue
                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                out.add(
                    mapOf(
                        "uri" to docUri.toString(),
                        "name" to (name ?: "document.pdf"),
                    ),
                )
            }
        }
        return out
    }

    private fun copyUriToCache(uri: Uri, displayName: String): String {
        val safe = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val out = File(cacheDir, "saf_${System.currentTimeMillis()}_$safe")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(out).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Cannot open $uri")
        return out.absolutePath
    }
}
