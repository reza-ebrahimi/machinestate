package outputs

import (
	"encoding/json"

	"machinestate/models"
)

// RenderJSON outputs the report as JSON
func RenderJSON(report *models.Report) (string, error) {
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// RenderJSONCompact outputs the report as compact JSON (no indentation)
func RenderJSONCompact(report *models.Report) (string, error) {
	data, err := json.Marshal(report)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// RenderJSONFromInterface outputs any interface as compact JSON
func RenderJSONFromInterface(v interface{}) (string, error) {
	data, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
