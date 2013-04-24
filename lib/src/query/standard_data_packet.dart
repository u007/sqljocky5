part of sqljocky;

class _StandardDataPacket implements Row {
  final List<dynamic> values;
  
  _StandardDataPacket(Buffer buffer, List<_FieldImpl> fieldPackets) :
      values = new List<dynamic>(fieldPackets.length) {
    for (var i = 0; i < fieldPackets.length; i++) {
      var s = buffer.readLengthCodedString();
      if (s == null) {
        values[i] = null;
        continue;
      }
      switch (fieldPackets[i].type) {
        case FIELD_TYPE_TINY: // tinyint/bool
        case FIELD_TYPE_SHORT: // smallint
        case FIELD_TYPE_INT24: // mediumint
        case FIELD_TYPE_LONGLONG: // bigint/serial
        case FIELD_TYPE_LONG: // int
          values[i] = int.parse(s);
          break;
        case FIELD_TYPE_NEWDECIMAL: // decimal
        case FIELD_TYPE_FLOAT: // float
        case FIELD_TYPE_DOUBLE: // double
          values[i] = double.parse(s);
          break;
        case FIELD_TYPE_BIT: // bit
          var value = 0;
          for (var num in s.codeUnits) {
            value = (value << 8) + num;
          }
          values[i] = value;
          break;
        case FIELD_TYPE_DATE: // date
        case FIELD_TYPE_DATETIME: // datetime
        case FIELD_TYPE_TIMESTAMP: // timestamp
          values[i] = DateTime.parse(s);
          break;
        case FIELD_TYPE_TIME: // time
          var parts = s.split(":");
          values[i] = new Duration(days: 0, hours: int.parse(parts[0]),
            minutes: int.parse(parts[1]), seconds: int.parse(parts[2]), 
            milliseconds: 0);
          break;
        case FIELD_TYPE_YEAR: // year
          values[i] = int.parse(s);
          break;
        case FIELD_TYPE_STRING: // char/binary/enum/set
        case FIELD_TYPE_VAR_STRING: // varchar/varbinary
          values[i] = s;
          break;
        case FIELD_TYPE_BLOB: // tinytext/text/mediumtext/longtext/tinyblob/mediumblob/blob/longblob
          var b = new Uint8List(s.length);
          b.setRange(0, s.length, s.codeUnits);
          values[i] = new Blob.fromString(s);
          break;
        case FIELD_TYPE_GEOMETRY: // geometry
          values[i] = s;
          break;
      }
    }
  }
  
  String toString() => "Value: $values";
}