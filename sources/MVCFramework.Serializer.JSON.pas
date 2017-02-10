// ***************************************************************************
//
// Delphi MVC Framework
//
// Copyright (c) 2010-2017 Daniele Teti and the DMVCFramework Team
//
// https://github.com/danieleteti/delphimvcframework
//
// ***************************************************************************
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************** }

unit MVCFramework.Serializer.JSON;

interface

{$I dmvcframework.inc}


uses MVCFramework.Serializer.Intf
    , Data.DB
    , System.Rtti
    , System.SysUtils
    , System.Classes
    , MVCFramework.TypesAliases, MVCFramework.DuckTyping, System.TypInfo
    ;

type
  TMVCJSONSerializer = class(TInterfacedObject, IMVCSerializer)
  private
    class var CTX: TRTTIContext;
    function SerializeFloatProperty(AObject: TObject;
      ARTTIProperty: TRttiProperty): TJSONValue; overload; deprecated;
    function SerializeFloatProperty(AElementType: TRTTIType; AValue: TValue): TJSONValue; overload;
    // function SerializeFloatField(AObject: TObject; ARttiField: TRttiField): TJSONValue;
    // function SerializeEnumerationProperty(AObject: TObject;
    // ARTTIProperty: TRttiProperty): TJSONValue; overload; deprecated;
    function SerializeEnumerationProperty(AElementType: TRTTIType; AValue: TValue): TJSONValue; overload;
    function SerializeTValue(AElementType: TRTTIType; AValue: TValue; AAttributes: TArray<TCustomAttribute>)
      : TJSONValue;
    function SerializeRecord(AElementType: TRTTIType; AValue: TValue; AAttributes: TArray<TCustomAttribute>)
      : TJSONValue;
    function SerializeEnumerationField(AObject: TObject;
      ARttiField: TRttiField): TJSONValue;
    function DeserializeFloat(ARTTIType: TRTTIType; AJSONValue: TJSONValue): TValue;
    function DeserializeEnumeration(ARTTIType: TRTTIType; AJSONValue: TJSONValue; AItemName: String): TValue;
    function DeserializeRecord(ARTTIType: TRTTIType; AJSONValue: TJSONValue;
      AAttributes: TArray<TCustomAttribute>; AItemName: String): TValue;
    function DeserializeArray(ARTTIType: TRTTIType; AJSONValue: TJSONValue;
      AAttributes: TArray<TCustomAttribute>; AItemName: String): TValue;
    function DeserializeTValue(AJValue: TJSONValue; AAttributes: TArray<TCustomAttribute>; AItemName: String): TValue;
    function DeserializeTValueWithDynamicType(AJValue: TJSONValue; AItemName: String): TValue;
    procedure DeSerializeStringStream(aStream: TStream;
      const aSerializedString: string; aEncoding: string);
    procedure DeSerializeBase64StringStream(aStream: TStream;
      const aBase64SerializedString: string);
    function ObjectToJSONObject(AObject: TObject;
      AIgnoredProperties: array of string): TJSONObject;
    function ObjectToJSONObjectFields(AObject: TObject): TJSONObject;
    function PropertyExists(JSONObject: TJSONObject;
      PropertyName: string): boolean;
    function GetPair(JSONObject: TJSONObject; PropertyName: string): TJSONPair;
    function JSONObjectToObject(Clazz: TClass;
      AJSONObject: TJSONObject): TObject;
    function SerializeRTTIElement(ElementType: TRTTIType;
      ElementAttributes: TArray<TCustomAttribute>; Value: TValue; out OutputValue: TJSONValue): boolean;
    procedure InternalJSONObjectToObject(AJSONObject: TJSONObject; AObject: TObject);
    function SerializeTValueAsFixedNullableType(AValue: TValue;
      AValueTypeInfo: PTypeInfo): TJSONValue;
    procedure InternalDeserializeObject(ASerializedObject: string; AObject: TObject; AStrict: boolean);
  protected
    { IMVCSerializer }
    function SerializeObject(AObject: TObject;
      AIgnoredProperties: array of string): string;
    function SerializeObjectStrict(AObject: TObject): String;
    function SerializeDataSet(ADataSet: TDataSet;
      AIgnoredFields: array of string): string;
    function SerializeCollection(AList: TObject;
      AIgnoredProperties: array of string): String;
    function SerializeCollectionStrict(AList: TObject): String;
    { IMVCDeserializer }
    procedure DeserializeObject(ASerializedObject: string; AObject: TObject);
    procedure DeserializeObjectStrict(ASerializedObject: String; AObject: TObject);
    procedure DeserializeCollection(ASerializedObjectList: string; AList: IMVCList; AClazz: TClass);
  public
    const
    SERIALIZER_NAME = 'DELPHIJSON';
  end;

implementation

uses
  ObjectsMappers, MVCFramework.Patches, MVCFramework.RTTIUtils,
  MVCFramework.Serializer.Commons, Winapi.Windows;

{ TMVCJSONSerializer }

procedure TMVCJSONSerializer.DeSerializeStringStream(aStream: TStream;
  const aSerializedString: string; aEncoding: string);
begin

end;

function TMVCJSONSerializer.DeserializeTValue(AJValue: TJSONValue; AAttributes: TArray<TCustomAttribute>;
  AItemName: String): TValue;
var
  lAttr: TValueAsType;
begin
  if TSerializerHelpers.AttributeExists<TValueAsType>(AAttributes, lAttr) then
  begin
    case lAttr.TValueTypeInfo.Kind of
      tkUString, tkString, tkLString, tkWString:
        begin
          Result := (AJValue as TJSONString).Value;
        end;
      tkInteger:
        begin
          Result := (AJValue as TJSONNumber).AsInt;
        end;
      tkInt64:
        begin
          Result := (AJValue as TJSONNumber).AsInt64;
        end;
      tkEnumeration:
        begin
          raise EMVCDeserializationException.Create('Booleans and enumerations are not supported');
        end;
    else
      raise EMVCDeserializationException.CreateFmt('Type non supported for TValue at item: ', [AItemName]);
    end;
  end
  else
  begin
    Result := DeserializeTValueWithDynamicType(AJValue, AItemName);
  end;
end;

function TMVCJSONSerializer.DeserializeTValueWithDynamicType(
  AJValue: TJSONValue; AItemName: String): TValue;
var
  lJTValueValue: TJSONValue;
  lTypeKind: TTypeKind;
  lStrType: string;
begin
  lStrType := AJValue.GetValue<TJSONString>('type').Value;
  lJTValueValue := AJValue.GetValue<TJSONValue>('value');
  lTypeKind := TSerializerHelpers.StringToTypeKind(lStrType);
  case lTypeKind of
    tkInteger:
      begin
        Result := (lJTValueValue as TJSONNumber).AsInt;
      end;
    tkEnumeration:
      begin
        Result := lJTValueValue is TJSONTrue;
      end;
    tkFloat:
      begin
        Result := (lJTValueValue as TJSONNumber).AsDouble;
      end;
    tkString, tkLString, tkWString, tkUString:
      begin
        Result := lJTValueValue.Value;
      end;
    tkInt64:
      begin
        Result := (lJTValueValue as TJSONNumber).AsInt64;
      end;
  else
    raise EMVCDeserializationException.CreateFmt('Type non supported for TValue %s at: ', [lStrType, AItemName]);
  end;
end;

function TMVCJSONSerializer.GetPair(JSONObject: TJSONObject; PropertyName: string): TJSONPair;
var
  pair: TJSONPair;
begin
  if not Assigned(JSONObject) then
    raise EMapperException.Create('JSONObject is nil');
  pair := JSONObject.Get(PropertyName);
  Result := pair;
end;

procedure TMVCJSONSerializer.InternalDeserializeObject(ASerializedObject: string;
  AObject: TObject; AStrict: boolean);
var
  lJSON: TJSONValue;
begin
  lJSON := TJSONObject.ParseJSONValue(ASerializedObject);
  try
    if lJSON <> nil then
    begin
      if lJSON is TJSONObject then
      begin
        if AStrict then
        begin
          // InternalJSONObjectToObjectFields(TJSONObject(lJSON), AObject)
        end
        else
          InternalJSONObjectToObject(TJSONObject(lJSON), AObject)
      end
      else
      begin
        raise EMVCDeserializationException.CreateFmt('Serialized string is a %s, expected JSON Object',
          [lJSON.ClassName]);
      end;
    end
    else
    begin
      raise EMVCDeserializationException.Create('Serialized string is not a valid JSON');
    end;
  finally
    lJSON.Free;
  end;
end;

procedure TMVCJSONSerializer.InternalJSONObjectToObject(AJSONObject: TJSONObject; AObject: TObject);
var
  lRttiType: TRTTIType;
  lProperties: TArray<TRttiProperty>;
  lProperty: TRttiProperty;
  f: string;
  jvalue: TJSONValue;
  v: TValue;
  o: TObject;
  list: IWrappedList;
  I: Integer;
  cref: TClass;
  attr: MapperItemsClassType;
  Arr: TJSONArray;
  n: TJSONNumber;
  SerStreamASString: string;
  _attrser: MapperSerializeAsString;
  ListMethod: TRttiMethod;
  ListItem: TValue;
  ListParam: TRttiParameter;
  lPropName: string;
  lTypeSerializer: IMVCTypeSerializer;
  lOutputValue: TValue;
  lInstanceField: TValue;
begin
  { TODO -oDaniele -cGeneral : Refactor this method }
  if not Assigned(AJSONObject) then
    raise EMapperException.Create('JSON Object cannot be nil');
  lRttiType := CTX.GetType(AObject.ClassInfo);
  lProperties := lRttiType.GetProperties;
  for lProperty in lProperties do
  begin
    if ((not lProperty.IsWritable) and (lProperty.PropertyType.TypeKind <> tkClass))
      or (TSerializerHelpers.HasAttribute<MapperTransientAttribute>(lProperty)) then
      Continue;
    lPropName := lProperty.Name;
    f := TSerializerHelpers.GetKeyName(lProperty, lRttiType);
    if Assigned(AJSONObject.Get(f)) then
      jvalue := AJSONObject.Get(f).JsonValue
    else
      Continue;

    lTypeSerializer := TMVCSerializersRegistry.GetTypeSerializer(SERIALIZER_NAME, lProperty.PropertyType.Handle);
    if lTypeSerializer <> nil then
    begin
      lInstanceField := lProperty.GetValue(TObject(AObject));
      lTypeSerializer.DeserializeInstance(
        lProperty.PropertyType, lProperty.GetAttributes, TObject(jvalue), lInstanceField);
      { Reference types MUST use the internal "AsObject" wghile value types can directly assign to InstanceField }
      if not lInstanceField.IsObject then
        lProperty.SetValue(TObject(AObject), lInstanceField);
    end
    else
    begin
      case lProperty.PropertyType.TypeKind of
        tkEnumeration:
          begin
            lProperty.SetValue(TObject(AObject),
              DeserializeEnumeration(lProperty.PropertyType, jvalue, lPropName));
          end;
        tkInteger, tkInt64:
          lProperty.SetValue(TObject(AObject), StrToIntDef(jvalue.Value, 0));
        tkFloat:
          begin
            lProperty.SetValue(TObject(AObject),
              DeserializeFloat(lProperty.PropertyType, jvalue));
          end;
        tkString, tkLString, tkWString, tkUString:
          begin
            lProperty.SetValue(TObject(AObject), jvalue.Value);
          end;
        tkRecord:
          begin
            lProperty.SetValue(TObject(AObject),
              DeserializeRecord(lProperty.PropertyType, jvalue, lProperty.GetAttributes, lPropName));
          end;
        tkArray:
          begin
            lProperty.SetValue(TObject(AObject),
              DeserializeArray(lProperty.PropertyType, jvalue, lProperty.GetAttributes, lPropName));
          end;
        tkClass: // try to restore child properties... but only if the collection is not nil!!!
          begin
            o := lProperty.GetValue(TObject(AObject)).AsObject;
            if Assigned(o) then
            begin
              if jvalue is TJSONNull then
              begin
                { TODO -oDaniele -cGeneral : How to handle this case at best? }
                // FreeAndNil(o);
                // lRttiProp.SetValue(AObject, nil);
              end
              else if o is TStream then
              begin
                if jvalue is TJSONString then
                begin
                  SerStreamASString := TJSONString(jvalue).Value;
                end
                else
                  raise EMapperException.Create('Expected JSONString in ' +
                    AJSONObject.Get(f).JsonString.Value);

                if TSerializerHelpers.HasAttribute<MapperSerializeAsString>(lProperty, _attrser) then
                begin
                  TSerializerHelpers.DeSerializeStringStream(TStream(o), SerStreamASString,
                    _attrser.Encoding);
                end
                else
                begin
                  TSerializerHelpers.DeSerializeBase64StringStream(TStream(o), SerStreamASString);
                end;
              end
              else if TDuckTypedList.CanBeWrappedAsList(o) then
              begin // restore collection
                if jvalue is TJSONArray then
                begin
                  Arr := TJSONArray(jvalue);
                  // look for the MapperItemsClassType on the property itself or on the property type
                  if Mapper.HasAttribute<MapperItemsClassType>(lProperty, attr) or
                    Mapper.HasAttribute<MapperItemsClassType>(lProperty.PropertyType,
                    attr) then
                  begin
                    cref := attr.Value;
                    list := WrapAsList(o);
                    for I := 0 to Arr.Count - 1 do
                    begin
                      list.Add(Mapper.JSONObjectToObject(cref,
                        Arr.Items[I] as TJSONObject));
                    end;
                  end
                  else // Ezequiel J. M�ller convert regular list
                  begin
                    ListMethod := CTX.GetType(o.ClassInfo).GetMethod('Add');
                    if (ListMethod <> nil) then
                    begin
                      for I := 0 to Arr.Count - 1 do
                      begin
                        ListItem := TValue.Empty;

                        for ListParam in ListMethod.GetParameters do
                          case ListParam.ParamType.TypeKind of
                            tkInteger, tkInt64:
                              ListItem := StrToIntDef(Arr.Items[I].Value, 0);
                            tkFloat:
                              ListItem := TJSONNumber(Arr.Items[I].Value).AsDouble;
                            tkString, tkLString, tkWString, tkUString:
                              ListItem := Arr.Items[I].Value;
                          end;

                        if not ListItem.IsEmpty then
                          ListMethod.Invoke(o, [ListItem]);
                      end;
                    end;
                  end;
                end
                else
                  raise EMapperException.Create('Cannot restore ' + f +
                    ' because the related json property is not an array');
              end
              else // try to deserialize into the property... but the json MUST be an object
              begin
                if jvalue is TJSONObject then
                begin
                  InternalJSONObjectToObject(TJSONObject(jvalue), o);
                end
                else if jvalue is TJSONNull then
                begin
                  FreeAndNil(o);
                  lProperty.SetValue(AObject, nil);
                end
                else
                  raise EMapperException.Create('Cannot deserialize property ' +
                    lProperty.Name);
              end;
            end;
          end;
      end; // case
    end;
  end;
end;

function TMVCJSONSerializer.JSONObjectToObject(Clazz: TClass; AJSONObject: TJSONObject): TObject;
var
  AObject: TObject;
begin
  AObject := TRTTIUtils.CreateObject(Clazz.QualifiedClassName);
  try
    InternalJSONObjectToObject(AJSONObject, AObject);
    Result := AObject;
  except
    on E: Exception do
    begin
      FreeAndNil(AObject);
      raise EMVCDeserializationException.Create(E.Message);
    end;
  end;
end;

function TMVCJSONSerializer.ObjectToJSONObject(AObject: TObject;
  AIgnoredProperties: array of string): TJSONObject;
var
  lType: TRTTIType;
  lProperties: TArray<TRttiProperty>;
  lProperty: TRttiProperty;
  f: string;
  JSONObject: TJSONObject;
  Arr: TJSONArray;
  list: IMVCList;
  Obj, o: TObject;
  DoNotSerializeThis: boolean;
  I: Integer;
  ThereAreIgnoredProperties: boolean;
  ts: TTimeStamp;
  sr: TStringStream;
  SS: TStringStream;
  _attrser: MapperSerializeAsString;
  lTypeSerializer: IMVCTypeSerializer;
  lJSONValue: TJSONValue;
  lSerializedJValue: TJSONValue;
begin
  ThereAreIgnoredProperties := Length(AIgnoredProperties) > 0;
  JSONObject := TJSONObject.Create;
  lType := CTX.GetType(AObject.ClassInfo);
  lProperties := lType.GetProperties;
  for lProperty in lProperties do
  begin
    f := TSerializerHelpers.GetKeyName(lProperty, lType);
    if ThereAreIgnoredProperties then
    begin
      DoNotSerializeThis := false;
      for I := low(AIgnoredProperties) to high(AIgnoredProperties) do
        if SameText(f, AIgnoredProperties[I]) then
        begin
          DoNotSerializeThis := True;
          Break;
        end;
      if DoNotSerializeThis then
        Continue;
    end;

    if TSerializerHelpers.HasAttribute<DoNotSerializeAttribute>(lProperty) then
      Continue;
    lTypeSerializer := TMVCSerializersRegistry.GetTypeSerializer(
      SERIALIZER_NAME,
      lProperty.PropertyType.Handle);
    if lTypeSerializer <> nil then
    begin
      lJSONValue := nil;
      lTypeSerializer.SerializeInstance(
        lProperty.PropertyType, lProperty.GetAttributes, lProperty.GetValue(AObject), TObject(lJSONValue));
      JSONObject.AddPair(f, lJSONValue);
    end
    else
    begin
      { if serializable then serialize, otherwise ignore it }
      if SerializeRTTIElement(lProperty.PropertyType, lProperty.GetAttributes,
        lProperty.GetValue(AObject), lSerializedJValue) then
        JSONObject.AddPair(f, lSerializedJValue);
    end;
  end;
  Result := JSONObject;

end;

function TMVCJSONSerializer.ObjectToJSONObjectFields(AObject: TObject): TJSONObject;
var
  _type: TRTTIType;
  _fields: TArray<TRttiField>;
  _field: TRttiField;
  f: string;
  JSONObject: TJSONObject;
  Obj, o: TObject;
  DoNotSerializeThis: boolean;
  I: Integer;
  JObj: TJSONObject;
  lSerializedJValue: TJSONValue;
begin
  JSONObject := TJSONObject.Create;
  try
    // add the $dmvc.classname property to allows a strict deserialization
    JSONObject.AddPair(DMVC_CLASSNAME, AObject.QualifiedClassName);
    _type := CTX.GetType(AObject.ClassInfo);
    _fields := _type.GetFields;
    for _field in _fields do
    begin
      f := TSerializerHelpers.GetKeyName(_field, _type);
      if SerializeRTTIElement(_field.FieldType, _field.GetAttributes, _field.GetValue(AObject), lSerializedJValue) then
        JSONObject.AddPair(f, lSerializedJValue);

      // case _field.FieldType.TypeKind of
      // tkInteger, tkInt64:
      // JSONObject.AddPair(f, TJSONNumber.Create(_field.GetValue(AObject)
      // .AsInteger));
      // tkFloat:
      // begin
      // JSONObject.AddPair(f, SerializeFloatField(AObject, _field));
      // end;
      // tkString, tkLString, tkWString, tkUString:
      // JSONObject.AddPair(f, _field.GetValue(AObject).AsString);
      // tkEnumeration:
      // begin
      // JSONObject.AddPair(f, SerializeEnumerationField(AObject, _field));
      // end;
      // tkClass:
      // begin
      // o := _field.GetValue(AObject).AsObject;
      // if Assigned(o) then
      // begin
      // if TDuckTypedList.CanBeWrappedAsList(o) then
      // begin
      // list := WrapAsList(o);
      // JObj := TJSONObject.Create;
      // JSONObject.AddPair(f, JObj);
      // JObj.AddPair(DMVC_CLASSNAME, o.QualifiedClassName);
      // Arr := TJSONArray.Create;
      // JObj.AddPair('items', Arr);
      // for Obj in list do
      // begin
      // Arr.AddElement(ObjectToJSONObjectFields(Obj));
      // end;
      // end
      // else
      // begin
      // JSONObject.AddPair(f,
      // ObjectToJSONObjectFields(_field.GetValue(AObject).AsObject));
      // end;
      // end
      // else
      // JSONObject.AddPair(f, TJSONNull.Create);
      // end;
      // end;
    end;
    Result := JSONObject;
  except
    FreeAndNil(JSONObject);
    raise;
  end;
end;

function TMVCJSONSerializer.SerializeFloatProperty(AObject: TObject;
  ARTTIProperty: TRttiProperty): TJSONValue;
begin
  if ARTTIProperty.PropertyType.QualifiedName = 'System.TDate' then
  begin
    if ARTTIProperty.GetValue(AObject).AsExtended = 0 then
      Result := TJSONNull.Create
    else
      Result := TJSONString.Create
        (ISODateToString(ARTTIProperty.GetValue(AObject).AsExtended))
  end
  else if ARTTIProperty.PropertyType.QualifiedName = 'System.TDateTime' then
  begin
    if ARTTIProperty.GetValue(AObject).AsExtended = 0 then
      Result := TJSONNull.Create
    else
      Result := TJSONString.Create
        (ISODateTimeToString(ARTTIProperty.GetValue(AObject).AsExtended))
  end
  else if ARTTIProperty.PropertyType.QualifiedName = 'System.TTime' then
    Result := TJSONString.Create(ISOTimeToString(ARTTIProperty.GetValue(AObject)
      .AsExtended))
  else
    Result := TJSONNumber.Create(ARTTIProperty.GetValue(AObject).AsExtended);
end;

function TMVCJSONSerializer.SerializeObject(AObject: TObject;
  AIgnoredProperties: array of string): string;
var
  lJSON: TJSONObject;
begin
  if AObject is TJSONValue then
    Exit(TJSONValue(AObject).ToJson);

  lJSON := ObjectToJSONObject(AObject, AIgnoredProperties);
  try
    Result := lJSON.ToJson;
  finally
    lJSON.Free;
  end;
end;

function TMVCJSONSerializer.SerializeObjectStrict(AObject: TObject): String;
begin
  raise EMVCSerializationException.Create('Not implemented');
end;

function TMVCJSONSerializer.SerializeRecord(AElementType: TRTTIType;
  AValue: TValue; AAttributes: TArray<TCustomAttribute>): TJSONValue;
var
  lTimeStamp: TTimeStamp;
begin
  if AElementType.QualifiedName = 'System.Rtti.TValue' then
  begin
    Result := SerializeTValue(AElementType, AValue, AAttributes);
  end
  else if AElementType.QualifiedName = 'System.SysUtils.TTimeStamp' then
  begin
    lTimeStamp := AValue.AsType<System.SysUtils.TTimeStamp>;
    Result := TJSONNumber.Create(TimeStampToMsecs(lTimeStamp));
  end
  else
    raise EMVCSerializationException.CreateFmt('Cannot serialize record: %s', [AElementType.ToString]);
end;

function TMVCJSONSerializer.SerializeRTTIElement(ElementType: TRTTIType;
  ElementAttributes: TArray<TCustomAttribute>; Value: TValue; out OutputValue: TJSONValue): boolean;
var
  ts: TTimeStamp;
  o: TObject;
  list: IMVCList;
  Arr: TJSONArray;
  Obj: TObject;
  _attrser: MapperSerializeAsString;
  SerEnc: TEncoding;
  sr: TStringStream;
  SS: TStringStream;
  lAttribute: MapperSerializeAsString;
  lAtt: TCustomAttribute;
  lEncodingName: string;
  buff: TBytes;
  lStreamAsString: string;
begin
  OutputValue := nil;
  Result := false;
  case ElementType.TypeKind of
    tkInteger, tkInt64:
      begin
        OutputValue := TJSONNumber.Create(Value.AsInteger);
      end;
    tkFloat:
      begin
        OutputValue := SerializeFloatProperty(ElementType, Value);
      end;
    tkString, tkLString, tkWString, tkUString:
      begin
        OutputValue := TJSONString.Create(Value.AsString);
      end;
    tkEnumeration:
      begin
        OutputValue := SerializeEnumerationProperty(ElementType, Value);
      end;
    tkRecord:
      begin
        OutputValue := SerializeRecord(ElementType, Value, ElementAttributes);
      end;
    tkClass:
      begin
        o := Value.AsObject;
        if Assigned(o) then
        begin
          list := TDuckTypedList.Wrap(o);
          if Assigned(list) then
          begin
            OutputValue := TJSONArray.Create;
            for Obj in list do
              if Assigned(Obj) then
                // nil element into the list are not serialized
                TJSONArray(OutputValue).AddElement(ObjectToJSONObject(Obj, []));
          end
          else
          begin
            OutputValue := ObjectToJSONObject(Value.AsObject, []);
          end;
        end
        else
        begin
          if TSerializerHelpers.HasAttribute<MapperSerializeAsString>(ElementType) then
            OutputValue := TJSONString.Create('')
          else
            OutputValue := TJSONNull.Create;
        end;
      end; // tkClass
  end;
  Result := OutputValue <> nil;
end;

function TMVCJSONSerializer.SerializeTValueAsFixedNullableType(AValue: TValue; AValueTypeInfo: PTypeInfo): TJSONValue;
begin
  // supports nulls
  if AValue.IsEmpty then
    Exit(TJSONNull.Create);

  // serialize the TValue internal value as specific type
  case AValueTypeInfo.Kind of
    tkString, tkUString, tkLString, tkWString:
      begin
        Result := TJSONString.Create(AValue.AsString);
      end;
    tkInteger:
      begin
        Result := TJSONNumber.Create(AValue.AsInteger);
      end;
    tkInt64:
      begin
        Result := TJSONNumber.Create(AValue.AsInt64);
      end;
  else
    raise EMVCSerializationException.Create('Unsupported type in SerializeTValueAsFixedType');
  end;
end;

function TMVCJSONSerializer.SerializeTValue(AElementType: TRTTIType; AValue: TValue;
  AAttributes: TArray<TCustomAttribute>)
  : TJSONValue;
var
  lTValueDataRTTIType: TRTTIType;
  lValue: TValue;
  lAtt: TValueAsType;
  lJSONValue: TJSONValue;
begin
  lValue := AValue.AsType<TValue>;
  if TSerializerHelpers.AttributeExists<TValueAsType>(AAttributes, lAtt) then
  begin
    Result := SerializeTValueAsFixedNullableType(lValue, lAtt.TValueTypeInfo)
  end
  else
  begin
    Result := TJSONObject.Create;
    try
      if lValue.IsEmpty then
      begin
        lJSONValue := TJSONNull.Create;
        TJSONObject(Result).AddPair('type', TJSONNull.Create);
      end
      else
      begin
        lTValueDataRTTIType := CTX.GetType(lValue.TypeInfo);
        if not SerializeRTTIElement(lTValueDataRTTIType, [], lValue, lJSONValue) then
          raise EMVCSerializationException.Create('Cannot serialize TValue');
        TJSONObject(Result).AddPair('type', TSerializerHelpers.GetTypeKindAsString(lValue.TypeInfo.Kind));
      end;
      TJSONObject(Result).AddPair('value', lJSONValue);
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TMVCJSONSerializer.SerializeCollection(AList: TObject;
  AIgnoredProperties: array of string): String;
var
  I: Integer;
  JV: TJSONObject;
  lList: IMVCList;
  lJArr: TJSONArray;
begin
  if Assigned(AList) then
  begin
    lList := WrapAsList(AList);
    lJArr := TJSONArray.Create;
    try
      // AList.OwnsObjects := AOwnsChildObjects;
      for I := 0 to lList.Count - 1 do
      begin
        JV := ObjectToJSONObject(lList.GetItem(I), AIgnoredProperties);
        // if Assigned(AForEach) then
        // AForEach(JV);
        lJArr.AddElement(JV);
      end;
      Result := lJArr.ToJson;
    finally
      lJArr.Free;
    end;
  end
  else
  begin
    raise EMVCSerializationException.Create('List is nil');
  end;
end;

function TMVCJSONSerializer.SerializeCollectionStrict(AList: TObject): String;
var
  I: Integer;
  JV: TJSONObject;
  lList: IMVCList;
  lJArr: TJSONArray;
begin
  if Assigned(AList) then
  begin
    lList := WrapAsList(AList);
    lJArr := TJSONArray.Create;
    try
      for I := 0 to lList.Count - 1 do
      begin
        JV := ObjectToJSONObjectFields(lList.GetItem(I));
        // if Assigned(AForEach) then
        // AForEach(JV);
        lJArr.AddElement(JV);
      end;
      Result := lJArr.ToJson;
    finally
      lJArr.Free;
    end;
  end
  else
  begin
    raise EMVCSerializationException.Create('List is nil');
  end;
end;

function TMVCJSONSerializer.PropertyExists(JSONObject: TJSONObject;
  PropertyName: string): boolean;
begin
  Result := Assigned(GetPair(JSONObject, PropertyName));
end;

function TMVCJSONSerializer.SerializeDataSet(ADataSet: TDataSet;
  AIgnoredFields: array of string): string;
begin
  raise EMVCSerializationException.Create('Not implemented');
end;

function TMVCJSONSerializer.SerializeEnumerationField(AObject: TObject;
  ARttiField: TRttiField): TJSONValue;
begin
  if ARttiField.FieldType.QualifiedName = 'System.Boolean' then
  begin
    if ARttiField.GetValue(AObject).AsBoolean then
      Result := TJSONTrue.Create
    else
      Result := TJSONFalse.Create;
  end
  else
  begin
    Result := TJSONNumber.Create(ARttiField.GetValue(AObject).AsOrdinal);
  end;
end;

function TMVCJSONSerializer.SerializeEnumerationProperty(AElementType: TRTTIType;
  AValue: TValue): TJSONValue;
begin
  if AElementType.QualifiedName = 'System.Boolean' then
  begin
    if AValue.AsBoolean then
      Result := TJSONTrue.Create
    else
      Result := TJSONFalse.Create;
  end
  else
  begin
    Result := TJSONNumber.Create(AValue.AsOrdinal);
  end;
end;

// function TMVCJSONSerializer.SerializeEnumerationProperty(AObject: TObject;
// ARTTIProperty: TRttiProperty): TJSONValue;
// begin
// if ARTTIProperty.PropertyType.QualifiedName = 'System.Boolean' then
// begin
// if ARTTIProperty.GetValue(AObject).AsBoolean then
// Result := TJSONTrue.Create
// else
// Result := TJSONFalse.Create;
// end
// else
// begin
// Result := TJSONNumber.Create(ARTTIProperty.GetValue(AObject).AsOrdinal);
// end;
// end;

//function TMVCJSONSerializer.SerializeFloatField(AObject: TObject;
//  ARttiField: TRttiField): TJSONValue;
//begin
//  if ARttiField.FieldType.QualifiedName = 'System.TDate' then
//  begin
//    if ARttiField.GetValue(AObject).AsExtended = 0 then
//      Result := TJSONNull.Create
//    else
//      Result := TJSONString.Create(ISODateToString(ARttiField.GetValue(AObject)
//        .AsExtended))
//  end
//  else if ARttiField.FieldType.QualifiedName = 'System.TDateTime' then
//  begin
//    if ARttiField.GetValue(AObject).AsExtended = 0 then
//      Result := TJSONNull.Create
//    else
//      Result := TJSONString.Create
//        (ISODateTimeToString(ARttiField.GetValue(AObject).AsExtended))
//  end
//  else if ARttiField.FieldType.QualifiedName = 'System.TTime' then
//    Result := TJSONString.Create(ISOTimeToString(ARttiField.GetValue(AObject)
//      .AsExtended))
//  else
//    Result := TJSONNumber.Create(ARttiField.GetValue(AObject).AsExtended);
//end;

function TMVCJSONSerializer.SerializeFloatProperty(AElementType: TRTTIType;
  AValue: TValue): TJSONValue;
begin
  if AElementType.QualifiedName = 'System.TDate' then
  begin
    if AValue.AsExtended = 0 then
      Result := TJSONNull.Create
    else
      Result := TJSONString.Create
        (ISODateToString(AValue.AsExtended))
  end
  else if AElementType.QualifiedName = 'System.TDateTime' then
  begin
    if AValue.AsExtended = 0 then
      Result := TJSONNull.Create
    else
      Result := TJSONString.Create
        (ISODateTimeToString(AValue.AsExtended))
  end
  else if AElementType.QualifiedName = 'System.TTime' then
    Result := TJSONString.Create(ISOTimeToString(AValue.AsExtended))
  else
    Result := TJSONNumber.Create(AValue.AsExtended);
end;

{ TMVCJSONDeserializer }

procedure TMVCJSONSerializer.DeserializeCollection(ASerializedObjectList: string; AList: IMVCList;
  AClazz: TClass);
var
  I: Integer;
  lJArr: TJSONArray;
  lJValue: TJSONValue;
begin
  if Trim(ASerializedObjectList) = '' then
    raise EMVCDeserializationException.Create('Invalid serialized data');
  lJValue := TJSONObject.ParseJSONValue(ASerializedObjectList);
  try
    if (lJValue = nil) or (not(lJValue is TJSONArray)) then
      raise EMVCDeserializationException.Create('Serialized data is not a valid JSON Array');
    lJArr := TJSONArray(lJValue);
    for I := 0 to lJArr.Count - 1 do
    begin
      AList.Add(JSONObjectToObject(AClazz, lJArr.Items[I] as TJSONObject));
    end;
  finally
    lJValue.Free;
  end;
end;

function TMVCJSONSerializer.DeserializeEnumeration(ARTTIType: TRTTIType; AJSONValue: TJSONValue;
  AItemName: String): TValue;
var
  lOutputValue: TValue;
begin
  if ARTTIType.QualifiedName = 'System.Boolean' then
  begin
    if AJSONValue is TJSONTrue then
      Result := True
    else if AJSONValue is TJSONFalse then
      Result := false
    else
      raise EMapperException.CreateFmt('Invalid value for property %s', [AItemName]);
  end
  else // it is an enumerated value but it's not a boolean.
  begin
    TValue.Make((AJSONValue as TJSONNumber).AsInt, ARTTIType.Handle, lOutputValue);
    Result := lOutputValue;
  end;
end;

function TMVCJSONSerializer.DeserializeFloat(ARTTIType: TRTTIType; AJSONValue: TJSONValue): TValue;
begin
  if ARTTIType.QualifiedName = 'System.TDate' then
  begin
    if AJSONValue is TJSONNull then
      Result := 0
    else
      Result := ISOStrToDateTime(AJSONValue.Value + ' 00:00:00');
  end
  else if ARTTIType.QualifiedName = 'System.TDateTime' then
  begin
    if AJSONValue is TJSONNull then
      Result := 0
    else
      Result := ISOStrToDateTime(AJSONValue.Value);
  end
  else if ARTTIType.QualifiedName = 'System.TTime' then
  begin
    if not(AJSONValue is TJSONNull) then
      if AJSONValue is TJSONString then
        Result := ISOStrToTime(AJSONValue.Value)
      else
        raise EMVCDeserializationException.CreateFmt
          ('Cannot deserialize [%s], expected [%s] got [%s]',
          [ARTTIType.QualifiedName, 'TJSONString', AJSONValue.ClassName]);
  end
  else { if _field.PropertyType.QualifiedName = 'System.Currency' then }
  begin
    if not(AJSONValue is TJSONNull) then
      if AJSONValue is TJSONNumber then
        Result := TJSONNumber(AJSONValue).AsDouble
      else
        raise EMVCDeserializationException.CreateFmt
          ('Cannot deserialize [%s], expected [%s] got [%s]',
          [ARTTIType.QualifiedName, 'TJSONNumber', AJSONValue.ClassName]);
  end;
end;

function TMVCJSONSerializer.DeserializeArray(ARTTIType: TRTTIType;
  AJSONValue: TJSONValue; AAttributes: TArray<TCustomAttribute>;
  AItemName: String): TValue;
begin

end;

procedure TMVCJSONSerializer.DeSerializeBase64StringStream(aStream: TStream;
  const aBase64SerializedString: string);
begin

end;

procedure TMVCJSONSerializer.DeserializeObject(ASerializedObject: string; AObject: TObject);
begin
  InternalDeserializeObject(ASerializedObject, AObject, false);
end;

procedure TMVCJSONSerializer.DeserializeObjectStrict(ASerializedObject: String;
  AObject: TObject);
begin
  InternalDeserializeObject(ASerializedObject, AObject, True);
end;

function TMVCJSONSerializer.DeserializeRecord(ARTTIType: TRTTIType; AJSONValue: TJSONValue;
  AAttributes: TArray<TCustomAttribute>; AItemName: String): TValue;
var
  lJNumber: TJSONNumber;
begin
  if ARTTIType.QualifiedName = 'System.Rtti.TValue' then
  begin
    Result := DeserializeTValue(AJSONValue, AAttributes, AItemName);
  end
  else if ARTTIType.QualifiedName = 'System.SysUtils.TTimeStamp'
  then
  begin
    lJNumber := AJSONValue as TJSONNumber;
    Result := TValue.From<TTimeStamp>(MSecsToTimeStamp(lJNumber.AsInt64));
  end
  else
    raise EMVCDeserializationException.CreateFmt('Type %s not supported for %s', [ARTTIType.QualifiedName, AItemName]);
end;

initialization

TMVCSerializersRegistry.RegisterSerializer('application/json', TMVCJSONSerializer.Create);

finalization

TMVCSerializersRegistry.UnRegisterSerializer('application/json');

end.
