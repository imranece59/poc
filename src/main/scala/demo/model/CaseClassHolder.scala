package demo.model
import java.sql.{Timestamp, Date}

import org.apache.spark.sql.types.StructType
import org.apache.spark.sql.types.StructField
import org.apache.spark.sql.types._

case class SkuDetails(
    skuName: String, 
    a: String,
    b: String,
    c : String, 
    d : String,
    e : String,
    f : String,
    g : String,
    h : String,
    i : String,
    j : String
)

