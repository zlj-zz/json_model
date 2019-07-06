import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'build_runner.dart' as br;

const tpl =
    "import 'package:json_annotation/json_annotation.dart';\n%t\npart '%s.g.dart';\n\n@JsonSerializable()\nclass %s {\n    %s();\n\n    %s\n    factory %s.fromJson(Map<String,dynamic> json) => _\$%sFromJson(json);\n    Map<String, dynamic> toJson() => _\$%sToJson(this);\n}\n";

void run(List<String> args) {
  String src;
  String dist;
  String tag;
  var parser = new ArgParser();
  parser.addOption('src',
      defaultsTo: './jsons',
      callback: (v) => src = v,
      help: "Specify the json directory.");
  parser.addOption('dist',
      defaultsTo: 'lib/models',
      callback: (v) => dist = v,
      help: "Specify the dist directory.");
  parser.addOption('tag',
      defaultsTo: '\$', callback: (v) => tag = v, help: "Specify the tag ");
  parser.parse(args);
  if (walk(src, dist, tag)) {
    br.run(['build', '--delete-conflicting-outputs']);
  }
}

//wbtvc: 转换"_"后的字符为大写，并且删除"_"。也就是转换文件名为驼峰类名
convName(String name) {
  replace(lastpos) {
    if (lastpos >= name.length) return -1;
    int pos = name.indexOf("_", lastpos + 1);
    // print("pos:$pos");
    if (pos != -1) {
      if (pos + 1 < name.length) {
        name = name.substring(0, pos) +
            name[pos + 1].toUpperCase() +
            name.substring(pos + 2);
        // print(name);
      } else {
        pos = -1;
      }
    }
    return pos;
  }

  var n = 0;
  while (n != -1) {
    n = replace(n);
  }
  name = name.replaceAll("_", "");
  // print("name:$name");
  return name;
}

//遍历JSON目录生成模板
bool walk(String srcDir, String distDir, String tag) {
  if (srcDir.endsWith("/")) srcDir = srcDir.substring(0, srcDir.length - 1);
  if (distDir.endsWith("/")) distDir = distDir.substring(0, distDir.length - 1);
  var src = Directory(srcDir);
  var list = src.listSync(recursive: true);
  String indexFile = "";
  if (list.isEmpty) return false;
  if (!Directory(distDir).existsSync()) {
    Directory(distDir).createSync(recursive: true);
  }
//  var tpl=path.join(Directory.current.parent.path,"model.tpl");
//  var template= File(tpl).readAsStringSync();
//  File(path.join(Directory.current.parent.path,"model.tplx")).writeAsString(jsonEncode(template));
  File file;
  list.forEach((f) {
    if (FileSystemEntity.isFileSync(f.path)) {
      file = File(f.path);
      var paths = path.basename(f.path).split(".");
      String name = paths.first;
      if (paths.last.toLowerCase() != "json" || name.startsWith("_")) return;
      if (name.startsWith("_")) return;
      //下面生成模板
      var map = json.decode(file.readAsStringSync());
      //为了避免重复导入相同的包，我们用Set来保存生成的import语句。
      var set = new Set<String>();
      StringBuffer attrs = new StringBuffer();
      (map as Map<String, dynamic>).forEach((key, v) {
        if (key.startsWith("_")) return;
        if (key.startsWith("@")) {
          if (key.startsWith("@import")) {
            set.add(key.substring(1) + " '$v'");
            return;
          }
          attrs.write(key);
          attrs.write(" ");
          attrs.write(v);
          attrs.writeln(";");
        } else {
          attrs.write(getType(v, set, name, tag));
          attrs.write(" ");
          attrs.write(key);
          attrs.writeln(";");
        }
        attrs.write("    ");
      });
      String className = name[0].toUpperCase() + name.substring(1);
      className = convName(className); //wbtvc: 转换文件名为驼峰类名
      var dist = format(tpl, [
        name,
        className,
        className,
        attrs.toString(),
        className,
        className,
        className
      ]);
      var _import = set.join(";\r\n");
      _import += _import.isEmpty ? "" : ";";
      dist = dist.replaceFirst("%t", _import);
      //将生成的模板输出
      var p =
          f.path.replaceFirst(srcDir, distDir).replaceFirst(".json", ".dart");
      File(p)
        ..createSync(recursive: true)
        ..writeAsStringSync(dist);
      var relative = p.replaceFirst(distDir + path.separator, "");
      indexFile += "export '$relative' ; \n";
    }
  });
  if (indexFile.isNotEmpty) {
    File(path.join(distDir, "index.dart")).writeAsStringSync(indexFile);
  }
  return indexFile.isNotEmpty;
}

String changeFirstChar(String str, [bool upper = true]) {
  return (upper ? str[0].toUpperCase() : str[0].toLowerCase()) +
      str.substring(1);
}

bool isBuiltInType(String type) {
  return ['int', 'num', 'string', 'double', 'map', 'list'].contains(type);
}

//将JSON类型转为对应的dart类型
String getType(v, Set<String> set, String current, tag) {
  current = current.toLowerCase();
  if (v is bool) {
    return "bool";
  } else if (v is num) {
    return "num";
  } else if (v is Map) {
    return "Map<String,dynamic>";
  } else if (v is List) {
    return "List";
  } else if (v is String) {
    //处理特殊标志
    if (v.startsWith("$tag[]")) {
      //wbt:处理$[]引用类数组，
      var n = v.indexOf("|");
      if (n != -1) {//wbt: 修改版必须在json中添加“|”符并且后面加真正引用的文件名
        var type = changeFirstChar(v.substring(3, n), false); //wbt:将首字母改为小写
        print("wbttest:$type, $n, $v");
        if (type.toLowerCase() != current && !isBuiltInType(type)) {
          var f = v.substring(n+1); //wbt：直接取文件名
          set.add('import "$f.dart"');
        }
        return "List<${changeFirstChar(type)}>"; //wbt: 强制首字母大写
      } else {//wbt: 这里为原版，不支持下划线文件名
        var type = changeFirstChar(v.substring(3), false); //wbt:将首字母改为小写
        if (type.toLowerCase() != current && !isBuiltInType(type)) {
          set.add('import "$type.dart"'); //wbt: 小写首字母的类做为文件名
        }
        return "List<${changeFirstChar(type)}>"; //wbt: 强制首字母大写
      }
    } else if (v.startsWith(tag)) {
      //wbt:引用类
      var n = v.indexOf("|");
      if (n != -1) {//wbt: 修改版必须在json中添加“|”符并且后面加真正引用的文件名
        var type = changeFirstChar(v.substring(1, n), false); //wbt:将首字母改为小写
        if (type.toLowerCase() != current) {
          var f = v.substring(n+1); //wbt：直接取文件名
          set.add('import "$f.dart"');
        }
        return changeFirstChar(type);
      } else {//wbt: 这里为原版，不支持下划线文件名
        var fileName = changeFirstChar(v.substring(1), false);
        if (fileName.toLowerCase() != current) {
          set.add('import "$fileName.dart"');
        }
        return changeFirstChar(fileName);
      }
    } else if (v.startsWith("@")) {
      return v;
    }
    return "String";
  } else {
    return "String";
  }
}

//替换模板占位符
String format(String fmt, List<Object> params) {
  int matchIndex = 0;
  String replace(Match m) {
    if (matchIndex < params.length) {
      switch (m[0]) {
        case "%s":
          return params[matchIndex++].toString();
      }
    } else {
      throw new Exception("Missing parameter for string format");
    }
    throw new Exception("Invalid format string: " + m[0].toString());
  }

  return fmt.replaceAllMapped("%s", replace);
}
