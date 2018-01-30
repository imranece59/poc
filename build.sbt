import sbt._
import Keys._


name := "demos"

version := "1.0"

scalaVersion := "2.11.8"



libraryDependencies += "com.googlecode.json-simple" % "json-simple" % "1.1"
libraryDependencies += "org.apache.spark" % "spark-core_2.11" % "2.2.0"
libraryDependencies += "org.apache.spark" % "spark-sql_2.11" % "2.2.0"
libraryDependencies += "org.apache.spark" % "spark-hive_2.11" % "2.2.0"


unmanagedBase := baseDirectory.value / "lib"

assemblyMergeStrategy in assembly := {

      case PathList("META-INF", "MANIFEST.MF") => MergeStrategy.discard    
      case PathList("org", "apache", "hadoop", "yarn", xs @ _*) => MergeStrategy.first
      case PathList("org", "objenesis", xs @ _*) => MergeStrategy.first

      case PathList("com.sun.jersey", "jersey-server", "bundles",xs @ _*) => MergeStrategy.discard
 
      case PathList("org", "apache", "spark","unused",xs @ _*) => MergeStrategy.first
      
      case PathList("org", "apache", "commons","logging", xs @ _*) => MergeStrategy.first

      case PathList("org", "apache", "commons","collections",xs @ _*) => MergeStrategy.first

      case PathList("org", "apache", "commons","beanutils",xs @ _*) => MergeStrategy.first

      case PathList("org", "aopalliance", "intercept",xs @ _*) => MergeStrategy.first

      case PathList("org", "aopalliance", "aop",xs @ _*) => MergeStrategy.first

      
      case PathList("javax", "xml",  xs @ _*) => MergeStrategy.first

      case PathList("javax", "ws",  xs @ _*) => MergeStrategy.first
      
      case PathList("javax", "servlet",  xs @ _*) => MergeStrategy.first

      case PathList("javax", "inject",  xs @ _*) => MergeStrategy.first

      case PathList("javax", "annotation",  xs @ _*) => MergeStrategy.first
    
      case PathList("javax", "activation",  xs @ _*) => MergeStrategy.first
      
      case PathList("com", "sun", "research","ws", xs @ _*) => MergeStrategy.first
    
      case PathList("org", "xerial", "snappy",xs @ _*) => MergeStrategy.first
    
      case PathList("org", "jets3t", "service",xs @ _*) => MergeStrategy.first

      case PathList("org", "slf4j",xs @ _*) => MergeStrategy.first  
   
      case PathList("org", "jboss","netty",xs @ _*) => MergeStrategy.first  

     case PathList("org", "codehaus","jackson",xs @ _*) => MergeStrategy.first    

     case PathList("org", "apache","http",xs @ _*) => MergeStrategy.first 

     case PathList("org", "apache","hadoop",xs @ _*) => MergeStrategy.first

      case PathList("org", "apache","curator",xs @ _*) => MergeStrategy.first
     
      case PathList("org", "apache","commons",xs @ _*) => MergeStrategy.first

     case PathList("org", "apache","avro",xs @ _*) => MergeStrategy.first

      case PathList("plugin.xml") => MergeStrategy.first
      
      case PathList("overview.html") => MergeStrategy.first
     
      case PathList("parquet.thrift") => MergeStrategy.first

      case "reference.conf" => MergeStrategy.concat 

      
       case x =>
    val oldStrategy = (assemblyMergeStrategy in assembly).value
     oldStrategy(x)
              
}    

EclipseKeys.withSource := true 

