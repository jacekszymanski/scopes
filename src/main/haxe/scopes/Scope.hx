/****
* Copyright (c) 2015-2022 Jacek Szymanski
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
* 
****/

package scopes;

import haxe.macro.TypedExprTools;
import haxe.macro.Expr;
import haxe.macro.Context;
import scopes.Util.*;

using haxe.macro.ExprTools;


class Scope {

  public static macro function withExits(ex: Expr) {

    return doWithExits(ex);
  }

#if macro
  private static function doWithExits(ex: Expr) {
    return switch (ex) {
      case { expr: EBlock(el) }: {
        transform(el, ex.pos);
      }
      default: ex.map(doWithExits);
    }

  }

  private static function transform(el: Array<Expr>, mpos: Position) {
    var ret = [];

    var arrName = genSym();
    var ignName = genSym();

    for (exp in el) switch (exp) {
      case macro @scope $expr:
        ret.push(macro $i{arrName}.unshift({ fail: null, run: function($ignName) $expr }));
      //case macro @scope(@as(${{ expr: EConst(CIdent(name)) }}) ${{ expr: EConst(CIdent(when)) }}) $expr:
      case { expr: EMeta({ name: "scope", params: [ {
        expr: EMeta({ name: "as", params: [ { expr: EConst(CIdent(name)) } ] }, when)
      } ] }, expr ) }:
        ret.push(macro $i{arrName}.unshift({ fail: $when,
                     run: ${{expr: EFunction(null, { ret: (macro :Void), expr: expr, args: [{ name: name, type: null }] } ),
                             pos: mpos }}}));
      case macro @scope($when) $expr:
        ret.push(macro $i{arrName}.unshift({ fail: $when, run: function($ignName) $expr }));
      case macro @SCOPE $expr:
        ret.push(macro $i{arrName}.unshift(
              { fail: null, run: function($ignName) try $expr catch (_: Dynamic) {} }));
      case { expr: EMeta({ name: "SCOPE", params: [ {
        expr: EMeta({ name: "as", params: [ { expr: EConst(CIdent(name)) } ] }, when)
      } ] }, expr ) }:
        ret.push(macro $i{arrName}.unshift({ fail: $when,
                     run: ${{expr: EFunction(null, { ret: (macro :Void),
                                               expr: (macro try $expr catch(_:Dynamic) {}),
                                               args: [{ name: name, type: null }] } ),
                             pos: mpos }}}));
      case macro @SCOPE($when) $expr:
        ret.push(macro $i{arrName}.unshift(
              { fail: $when, run: function($ignName) try $expr catch (_: Dynamic) {} }));
      case { expr: EMeta({ name: "closes", params: []}, { expr: EVars(vars), pos: pos }) }: {
        for (vardecl in vars) {
          ret.push({ expr: EVars([ vardecl ]), pos: pos });
          ret.push(macro $i{arrName}.unshift({ fail: null, run: function($ignName) $i{vardecl.name}.close() }));
        }
      }
      case { expr: EMeta({ name: "closes", params: [ { expr: EConst(CString(func)) } ]},
                         { expr: EVars(vars), pos: pos }) }: {
        for (vardecl in vars) {
          ret.push({ expr: EVars([ vardecl ]), pos: pos });
          ret.push(macro $i{arrName}.unshift({ fail: null, run: function($ignName) $i{vardecl.name}.$func() }));
        }
      }
      case { expr: EMeta({ name: "CLOSES", params: []}, { expr: EVars(vars), pos: pos }) }: {
        for (vardecl in vars) {
          ret.push({ expr: EVars([ vardecl ]), pos: pos });
          ret.push(macro $i{arrName}.unshift(
                { fail: null, run: function($ignName) try $i{vardecl.name}.close() catch(_: Dynamic) {} }));
        }
      }
      case { expr: EMeta({ name: "CLOSES", params: [ { expr: EConst(CString(func)) } ]},
                         { expr: EVars(vars), pos: pos }) }: {
        for (vardecl in vars) {
          ret.push({ expr: EVars([ vardecl ]), pos: pos });
          ret.push(macro $i{arrName}.unshift(
                { fail: null, run: function($ignName) try $i{vardecl.name}.$func() catch (_: Dynamic) {} }));
        }
      }
      default:
        ret.push(exp);
    }

    var statusName = genSym();
    var counter = genSym();
    var excName = genSym();

    var bindings = { expr: (macro
      var $arrName: Array<scopes.Scope.ExitFunc> = [],
          $statusName: Null<Bool> = null

    ).expr, pos: mpos};

    var retx = scopes.Protect.protectBuild(bindings, macro $b{ret}, macro function ($excName) {

      for ($i{counter} in $i{arrName}) {
        if (($i{counter}.fail == null) ||
                ($i{counter}.fail == $i{statusName}))
          ($i{counter}.run)(null);
        else if (!Std.isOfType($i{counter}.fail, Bool) && Std.isOfType($i{excName}, $i{counter}.fail)) {
          ($i{counter}.run)($i{excName});
        }
      }


    });

    //Sys.println(TypedExprTools.toString(Context.typeExpr(retx), true));

    var detyped = Context.getTypedExpr(Context.typeExpr(retx));

    checkReturns(detyped, arrName);

    return retx;
  }

  private static function recParseDotted(ex: Expr, n: String) {
    return switch(ex.expr) {
      case EConst(CIdent(name)): '${name}.${n}';
      case EField(exx, nn): recParseDotted(exx, '${nn}.${n}');
      default: Context.fatalError('cannot unparse type name, got ${n} so far', ex.pos);

    };
  }

  private static function checkReturns(ex: Expr, arr: String) {
    return switch(ex) {
      case macro $arr.unshift({ fail: $when, run: ${{ expr: EFunction(_, fun) }} }): checkReturnsSub(fun.expr); ex;
      default: ex.map(checkReturns.bind(_, arr));
    }

  }

  private static function checkReturnsSub(ex: Expr) {
    return switch(ex) {
      case { expr: EReturn(_) }: Context.fatalError("return not allowed in scope exits", ex.pos);
      case { expr: EFunction(_, _) }: ex;
      default: ex.map(checkReturnsSub);
    }
  }

#else
  private static function transform(el: Array<Expr>)
    throw "Only for macros";
#end

}

typedef ExitFunc = {
  var fail: Null<Dynamic>;
  var run: Dynamic;
}
