/*
 * Copyright (C) 2009, Martin Robinson
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#pragma once

#include "Image.h"
#include "SharedBuffer.h"
#include <wtf/HashMap.h>
#include <wtf/TZoneMalloc.h>
#include <wtf/URL.h>
#include <wtf/text/StringHash.h>

namespace WebCore {

class SelectionData {
    WTF_MAKE_TZONE_ALLOCATED(SelectionData);
public:
    void setText(const String&);
    const String& text() const { return m_text; }
    bool hasText() const { return !m_text.isEmpty(); }
    void clearText() { m_text = emptyString(); }

    void setMarkup(const String& newMarkup) { m_markup = newMarkup; }
    const String& markup() const { return m_markup; }
    bool hasMarkup() const { return !m_markup.isEmpty(); }
    void clearMarkup() { m_markup = emptyString(); }

    void setURL(const URL&, const String&);
    const URL& url() const { return m_url; }
    const String& urlLabel() const;
    bool hasURL() const { return !m_url.isEmpty() && m_url.isValid(); }
    void clearURL() { m_url = URL(); }

    void setURIList(const String&);
    const String& uriList() const { return m_uriList; }
    const Vector<String>& filenames() const { return m_filenames; }
    bool hasURIList() const { return !m_uriList.isEmpty(); }
    bool hasFilenames() const { return !m_filenames.isEmpty(); }
    void clearURIList() { m_uriList = emptyString(); }

    void setImage(RefPtr<Image>&& newImage) { m_image = WTFMove(newImage); }
    const RefPtr<Image>& image() const { return m_image; }
    bool hasImage() const { return m_image; }
    void clearImage() { m_image = nullptr; }

    void setCanSmartReplace(bool canSmartReplace) { m_canSmartReplace = canSmartReplace; }
    bool canSmartReplace() const { return m_canSmartReplace; }

    void addBuffer(const String& type, const Ref<SharedBuffer>& buffer) { m_buffers.add(type, buffer.get()); }
    const UncheckedKeyHashMap<String, Ref<SharedBuffer>>& buffers() const { return m_buffers; }
    SharedBuffer* buffer(const String& type) { return m_buffers.get(type); }
    void clearBuffers() { m_buffers.clear(); }

    void setCustomData(Ref<SharedBuffer>&& buffer) { m_customData = WTFMove(buffer); }
    const RefPtr<SharedBuffer>& customData() const { return m_customData; }
    bool hasCustomData() const { return !!m_customData; }
    void clearCustomData() { m_customData = nullptr; }

    void clearAll();
    void clearAllExceptFilenames();

    SelectionData(const String& text, const String& markup, const URL&, const String& uriList, RefPtr<WebCore::Image>&&, RefPtr<WebCore::SharedBuffer>&&, bool);
    SelectionData() = default;

private:
    String m_text;
    String m_markup;
    URL m_url;
    String m_uriList;
    Vector<String> m_filenames;
    RefPtr<Image> m_image;
    bool m_canSmartReplace { false };
    RefPtr<SharedBuffer> m_customData;
    UncheckedKeyHashMap<String, Ref<SharedBuffer>> m_buffers;
};

} // namespace WebCore
