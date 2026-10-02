package;

#if android
import android.Tools;
import android.Permissions;
import android.PermissionsList;
#end
import lime.app.Application;
import lime.system.System as LimeSystem;
import openfl.events.UncaughtErrorEvent;
import openfl.utils.Assets as OpenFlAssets;
import openfl.Lib;
import haxe.CallStack.StackItem;
import haxe.CallStack;
import haxe.io.Path;
#if ios
import haxe.io.Bytes;
#end
import sys.FileSystem;
import sys.io.File;
import flash.system.System;
import flixel.FlxG;

/**
 * ...
 * @author: Saw (M.A. Jigsaw)
 */

using StringTools;

class SUtil
{
	public static var errMsg:String;
	public static function getPath():String
	{
		#if android
        return Tools.getExternalStorageDirectory() + '/' + '.' + Application.current.meta.get('file') + '/';
		#end

		#if ios
		return LimeSystem.documentsDirectory;
		#end

		#if windows
		return '';
		#end
	}

	// ==================== [PE-iOS] 首次启动自动释放内置资源 ====================
	// 旧逻辑：必须手动把 Assets.zip 解压到 Documents 下才有 assets / mods，
	// 否则一进游戏就弹窗「you didn't extract the files from the Assets .zip」然后退出。
	// 新逻辑：App 包里自带一份 resources.zip（CI 打的），首次启动自动解开，
	// 用户装完 IPA 直接就能玩，不再需要手动解压。
	#if ios
	public static function ensureAssets():Void
	{
		var base:String = getPath();
		if (base == null || base.length < 1) return;

		var marker:String = base + 'pe_ios_assets_done.txt';
		if (FileSystem.exists(marker) && FileSystem.exists(base + 'assets') && FileSystem.exists(base + 'mods'))
			return;

		var bytes:Bytes = null;
		for (id in ['assets/resources.zip', 'resources.zip', 'assets/preload/resources.zip'])
		{
			try { bytes = OpenFlAssets.getBytes(id); } catch (e:Dynamic) { bytes = null; }
			if (bytes != null && bytes.length > 16)
			{
				trace('[PE-iOS] 找到内置资源包: ' + id + ' (' + bytes.length + ' bytes)');
				break;
			}
			bytes = null;
		}

		if (bytes == null || bytes.length < 16)
		{
			trace('[PE-iOS] 没有内置 resources.zip，跳过自动释放（将使用旧的手动解压方式）');
			return;
		}

		trace('[PE-iOS] 首次启动：正在释放内置资源到 ' + base + ' ...');
		var count:Int = unzipInto(bytes, base);
		if (count > 0)
		{
			try { File.saveContent(marker, 'released ' + count + ' files'); } catch (e:Dynamic) {}
			trace('[PE-iOS] 资源释放完成，共 ' + count + ' 个文件');
		}

		if (!FileSystem.exists(base + 'mods'))
		{
			try { FileSystem.createDirectory(base + 'mods'); } catch (e:Dynamic) {}
		}
		if (!FileSystem.exists(base + 'assets'))
		{
			try { FileSystem.createDirectory(base + 'assets'); } catch (e:Dynamic) {}
		}
	}

	static function unzipInto(bytes:Bytes, destDir:String):Int
	{
		var count:Int = 0;
		var entries:Array<haxe.zip.Entry> = null;
		try
		{
			entries = new haxe.zip.Reader(new haxe.io.BytesInput(bytes)).read();
		}
		catch (e:Dynamic)
		{
			trace('[PE-iOS] 解压失败（不是合法 zip？）: ' + e);
			return 0;
		}

		for (entry in entries)
		{
			if (entry == null || entry.fileName == null) continue;
			var name:String = entry.fileName.split('\\').join('/');
			if (name.length < 1 || name.charAt(name.length - 1) == '/') continue; // 目录项跳过

			var data:Bytes = entry.data;
			if (data != null)
			{
				// 压缩过的条目需要解压；没压缩的（stored）解压会抛异常，直接用原数据
				try { data = haxe.zip.Tools.uncompress(data); } catch (e:Dynamic) {}
			}
			if (data == null) continue;

			var out:String = destDir + name;
			var slash:Int = out.lastIndexOf('/');
			if (slash > 0) mkdirs(out.substring(0, slash));

			try
			{
				File.saveBytes(out, data);
				count++;
			}
			catch (e:Dynamic)
			{
				trace('[PE-iOS] 写入失败 ' + out + ': ' + e);
			}
		}
		return count;
	}

	static function mkdirs(dir:String):Void
	{
		if (dir == null || dir.length < 2 || FileSystem.exists(dir)) return;
		var slash:Int = dir.lastIndexOf('/');
		if (slash > 1) mkdirs(dir.substring(0, slash));
		try { FileSystem.createDirectory(dir); } catch (e:Dynamic) {}
	}
	#end
	// =====================================================================

	public static function doTheCheck()
	{
		#if ios
		// 先把内置资源释放出来，再去检查目录在不在
		ensureAssets();
		#end

		if (!FileSystem.exists(SUtil.getPath() + 'assets') && !FileSystem.exists(SUtil.getPath() + 'mods'))
			{
				SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the files from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
				CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
				System.exit(0);
			}
			else
			{
				if (!FileSystem.exists(SUtil.getPath() + 'assets'))
				{
					SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the assets folder from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
					CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
					System.exit(0);
				}

				if (!FileSystem.exists(SUtil.getPath() + 'mods'))
				{
					SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the mods folder from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
					CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
					System.exit(0);
				}
			}
	}

	public static function gameCrashCheck()
	{
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
	}

	public static function onCrash(e:UncaughtErrorEvent):Void
	{
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();
		dateNow = StringTools.replace(dateNow, " ", "_");
		dateNow = StringTools.replace(dateNow, ":", "'");

		var path:String = "crash/" + "crash_" + dateNow + ".txt";
		var errMsg:String = "";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += e.error;

		if (!FileSystem.exists(SUtil.getPath() + "crash"))
		FileSystem.createDirectory(SUtil.getPath() + "crash");

		File.saveContent(SUtil.getPath() + path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));
		Sys.println("Making a simple alert ...");

		FlxG.switchState(new CrashState());
	}

	private static function applicationAlert(title:String, description:String)
	{
		Application.current.window.alert(description, title);
	}

	#if mobile
	public static function saveContent(fileName:String = 'file', fileExtension:String = '.json', fileData:String = 'you forgot something to add in your code')
	{
		if (!FileSystem.exists(SUtil.getPath() + 'saves'))
			FileSystem.createDirectory(SUtil.getPath() + 'saves');

		File.saveContent(SUtil.getPath() + 'saves/' + fileName + fileExtension, fileData);
		SUtil.applicationAlert('Done :)!', 'File Saved Successfully!');
	}

	public static function saveClipboard(fileData:String = 'you forgot something to add in your code')
	{
		openfl.system.System.setClipboard(fileData);
		SUtil.applicationAlert('Finished!', 'Data Saved to Clipboard Successfully!');
	}

	public static function copyContent(copyPath:String, savePath:String)
	{
		if (!FileSystem.exists(savePath))
			File.saveBytes(savePath, OpenFlAssets.getBytes(copyPath));
	}
	#end
}
