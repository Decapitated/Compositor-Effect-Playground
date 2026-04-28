struct StencilData {
	int id;
	bool highlighted;
	bool selected;
};

StencilData extract_stencil_data(int stencil) {
	StencilData data;

    data.id = stencil & 63;
    data.highlighted = (stencil & 64) != 0;
    data.selected = (stencil & 128) != 0;

	return data;
}