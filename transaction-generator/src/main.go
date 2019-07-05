// Copyright 2020 Google Inc. All rights reserved.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

//     http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	_ "github.com/lib/pq"
)

const debug = 0

var (
	defaultPort     = "5432"
	defaultUser     = "postgres"
	defaultSslMode  = "disable"
)

func doSelectCustomer(db *sql.DB, customerIdQuery int) {

	customerQuery := "SELECT id, name " +
			" FROM pitr_demo.pitr_db_schema.customer " +
			"WHERE id = $1"


	row := db.QueryRow(customerQuery, customerIdQuery)

	log.Println("Query : ", customerQuery, "Parameters: ", customerIdQuery)

	var customerId int
	var customerName string
	if err := row.Scan(&customerId, &customerName); err != nil {
		// handle this error
		log.Fatal(err)
	}
	log.Println(customerId, customerName)

}

func doSelectInvoice(db *sql.DB, customerIdQuery int) {

	invoiceQuery := "SELECT id, customer_id, description " +
			"  FROM pitr_demo.pitr_db_schema.invoice " +
			"WHERE customer_id = $1"

	rows, err := db.Query( invoiceQuery, customerIdQuery)

	defer rows.Close()

	log.Println("Query : ", invoiceQuery, "Parameters: ", customerIdQuery)

	for rows.Next() {
		var invoiceId int
		var customerId int
		var invoiceDesc string
		if err = rows.Scan(&invoiceId, &customerId, &invoiceDesc); err != nil {
			// handle this error
			log.Fatal(err)
		}
		log.Println(invoiceId, customerId, invoiceDesc)
	}

	// get any error encountered during iteration
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
}

func doCreateCustomer(db *sql.DB) int {

	sqlStatement := `
      INSERT INTO pitr_demo.pitr_db_schema.customer (name)
      VALUES ($1)
      RETURNING id`
	id := 0
	if err := db.QueryRow(sqlStatement,
	                      "customer_name_from_golang").Scan(&id); err != nil {
		log.Fatal(err)
	}
	return id
}

func doCreateInvoice(db *sql.DB, customerId int) int {

	sqlStatement := `
      INSERT INTO pitr_demo.pitr_db_schema.invoice (customer_id, description)
      VALUES ($1, $2)
      RETURNING id`
	id := 0
	if err := db.QueryRow(sqlStatement,
	                      customerId,
			      "invoice description from_golang").Scan(&id); err != nil {
		log.Fatal(err)
	}

	return id
}

// obtainEnvValue retrives values from environemnt variables.
// If the environemnt variable is set, the value is returned
// If the environment variable is not set,
//     the supplyed default value in defaultValue is returned
//   If defaultValue points to nil (the value is required)
//      a fatal error results
func obtainEnvValue(key string, defaultValue *string) string {
	val, envSet := os.LookupEnv(key)
	if !envSet {
		logMsgPrefix := fmt.Sprintf("Env var %s is not set,", key)
		if defaultValue == nil {
			log.Fatal(logMsgPrefix, " yet it is required.")
		} else {
			log.Printf("%s use default value: %s", logMsgPrefix, *defaultValue)
			return *defaultValue
		}
	}
	return val

}

func main() {

	var err error
	var db *sql.DB
	customerCreateCount := 1
	invoicePerCustomerCount := 10

	// onbtain values from environment variablres
	user := obtainEnvValue("USERNAME", &defaultUser)
	host := obtainEnvValue("HOST", nil)
	port := obtainEnvValue("PORT", &defaultPort)
	dbname := obtainEnvValue("DBNAME", nil)
	sslmode := obtainEnvValue("SSLMODE", &defaultSslMode)
	password := obtainEnvValue("PASSWORD", nil)

	args := os.Args[1:]

	if len(args) != 0 {
		if customerCreateCount, err = strconv.Atoi(args[0]); err != nil {
			log.Fatal(err)
		}
	}

	log.Printf("Transaction Generator will create %d customer records, " +
	           "and %d invoices for each customer",
		   customerCreateCount,
		   invoicePerCustomerCount)

	connectInfo := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		user, password, host, port, dbname, sslmode)

	db, err = sql.Open("postgres", connectInfo)

	defer db.Close()

	if err != nil {
		log.Fatal(err)
	}

	for i := 0; i < customerCreateCount; i++ {

		customerId := doCreateCustomer(db)
		for j := 0; j < invoicePerCustomerCount; j++ {
			doCreateInvoice(db, customerId)

		}
		if i == 0 {
			// select the first row from the database to verify persistence
			doSelectCustomer(db, 1)
			doSelectInvoice(db, 1)
		}
		// wait 1 second
		time.Sleep(1 * time.Second)

	}

}
